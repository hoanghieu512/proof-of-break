// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BountyRegistry} from "../src/BountyRegistry.sol";
import {DemoVault} from "../src/DemoVault.sol";
import {VaultChecker, IVaultLedger} from "../src/VaultChecker.sol";

/**
 * @title OpenBounty
 * @notice Deploys one fresh vault + checker and opens a bounty on the existing
 *         Registry. The restock button.
 *
 * @dev Needed because a bounty dies permanently the moment anyone calls
 *      `deposit(1e18)` on its target directly — the griefing vector in the
 *      README — and because every successful claim in Task 7 consumes one.
 *      Recovering from either must not mean redeploying the Registry, which
 *      would invalidate every address already written down.
 *
 *      Always deploys a NEW vault. Reusing an existing one would inherit
 *      whatever state broke it, and `openBounty` would refuse the bounty for
 *      an already-broken invariant anyway.
 *
 *        REGISTRY=0x... REWARD_WEI=500000000000000000 \
 *        forge script script/OpenBounty.s.sol:OpenBounty \
 *          --rpc-url $ARC_RPC_URL --broadcast --slow \
 *          --verify --verifier blockscout \
 *          --verifier-url https://testnet.arcscan.app/api/
 *
 *      REWARD_WEI defaults to 0.5 USDC. Remember Arc's native USDC is 18
 *      decimals: 5e17 is half a dollar, 5e5 is nothing at all.
 */
contract OpenBounty is Script {
    string internal constant SIGNATURE = "deposit(uint256)";

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address registryAddress = vm.envAddress("REGISTRY");
        uint256 reward = vm.envOr("REWARD_WEI", uint256(0.5 ether));

        BountyRegistry registry = BountyRegistry(registryAddress);

        console.log("registry      ", registryAddress);
        console.log("open before   ", registry.openBountyIds().length);
        console.log("reward (wei)  ", reward);

        vm.startBroadcast(deployerKey);

        DemoVault vault = new DemoVault();
        VaultChecker checker = new VaultChecker(IVaultLedger(address(vault)));
        uint256 id = registry.openBounty{value: reward}(address(vault), checker, SIGNATURE);

        vm.stopBroadcast();

        console.log("=====================================");
        console.log("bounty id     ", id);
        console.log("DemoVault     ", address(vault));
        console.log("VaultChecker  ", address(checker));
        console.log("open after    ", registry.openBountyIds().length);
        console.log("totalEscrowed ", registry.totalEscrowed());
    }
}
