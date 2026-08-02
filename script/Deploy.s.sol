// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BountyRegistry} from "../src/BountyRegistry.sol";
import {DemoVault} from "../src/DemoVault.sol";
import {VaultChecker, IVaultLedger} from "../src/VaultChecker.sol";

/**
 * @title Deploy
 * @notice Puts the whole system on Arc Testnet and opens the bounty board.
 *
 * @dev Run with `--slow`. Day 1 established that on Arc a transaction hash is
 *      not a promise of inclusion: at burst rate the RPC accepted 29 of 60
 *      transactions and mined 5 (docs/measurements/day1-report.md). `--slow`
 *      sends one transaction at a time and waits for each receipt, which is the
 *      difference between a deployment and a list of addresses that may or may
 *      not exist.
 *
 *        forge script script/Deploy.s.sol:Deploy \
 *          --rpc-url $ARC_RPC_URL --broadcast --slow \
 *          --verify --verifier blockscout \
 *          --verifier-url https://testnet.arcscan.app/api/
 *
 *      WHY FIVE BOUNTIES AND NOT ONE
 *
 *      A target is an ordinary public contract, so anyone can call
 *      `deposit(1e18)` on it directly and kill that bounty forever — the
 *      griefing vector recorded in the README. One bounty would make the demo
 *      depend on a single egg surviving until the camera rolls. Five gives
 *      spares, and each claim in Task 7 consumes exactly one.
 *
 *      The rewards deliberately differ. Task 6 requires the agent to pick its
 *      own work off the board; if every bounty were identical there would be
 *      nothing to observe about the choice.
 */
contract Deploy is Script {
    uint256 internal constant BOUNTY_COUNT = 5;
    string internal constant SIGNATURE = "deposit(uint256)";

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // 0.25 / 0.5 / 0.75 / 1.0 / 1.5 USDC. Native USDC on Arc has 18
        // decimals, so `ether` here reads as USDC — see the note in
        // BountyRegistry about why 1e6 would be a silent disaster.
        uint256[BOUNTY_COUNT] memory rewards =
            [uint256(0.25 ether), 0.5 ether, 0.75 ether, 1 ether, 1.5 ether];

        uint256 totalRewards;
        for (uint256 i = 0; i < BOUNTY_COUNT; ++i) {
            totalRewards += rewards[i];
        }

        console.log("deployer     ", deployer);
        console.log("balance (wei)", deployer.balance);
        console.log("to escrow    ", totalRewards);
        require(deployer.balance > totalRewards, "deployer cannot fund the bounties");

        vm.startBroadcast(deployerKey);

        BountyRegistry registry = new BountyRegistry();
        console.log("BountyRegistry", address(registry));

        for (uint256 i = 0; i < BOUNTY_COUNT; ++i) {
            DemoVault vault = new DemoVault();
            VaultChecker checker = new VaultChecker(IVaultLedger(address(vault)));
            uint256 id = registry.openBounty{value: rewards[i]}(
                address(vault), checker, SIGNATURE
            );

            console.log("---- bounty", id);
            console.log("  DemoVault   ", address(vault));
            console.log("  VaultChecker", address(checker));
            console.log("  reward (wei)", rewards[i]);
        }

        vm.stopBroadcast();

        console.log("=====================================");
        console.log("registry     ", address(registry));
        console.log("bountyCount  ", registry.bountyCount());
        console.log("totalEscrowed", registry.totalEscrowed());
    }
}
