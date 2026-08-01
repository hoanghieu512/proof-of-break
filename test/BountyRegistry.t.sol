// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {BountyRegistry} from "../src/BountyRegistry.sol";
import {DemoVault} from "../src/DemoVault.sol";
import {IChecker} from "../src/IChecker.sol";
import {VaultChecker, IVaultLedger} from "../src/VaultChecker.sol";

/// @notice A checker whose `target()` reverts, so the Registry cannot confirm
///         what it watches. Must be refused rather than trusted.
contract TargetRevertingChecker is IChecker {
    function checkInvariant() external pure returns (bool) {
        return true;
    }

    function target() external pure returns (address) {
        revert("target() unavailable");
    }

    function description() external pure returns (string memory) {
        return "unusable";
    }
}

/// @notice A checker that names its target honestly but cannot answer the
///         question that matters.
contract CheckRevertingChecker is IChecker {
    address private immutable _target;

    constructor(address target_) {
        _target = target_;
    }

    function checkInvariant() external pure returns (bool) {
        revert("cannot evaluate");
    }

    function target() external view returns (address) {
        return _target;
    }

    function description() external pure returns (string memory) {
        return "always reverts";
    }
}

contract BountyRegistryTest is Test {
    BountyRegistry internal registry;
    DemoVault internal vault;
    VaultChecker internal checker;

    address internal sponsor = makeAddr("sponsor");
    address internal otherSponsor = makeAddr("otherSponsor");
    address internal stranger = makeAddr("stranger");

    string internal constant SIG = "deposit(uint256)";

    /// @dev Cached in setUp on purpose. Calling `registry.ONE_USDC()` inline
    ///      inside a `{value: ...}` block is an external call, and if
    ///      `vm.expectRevert` is already armed it consumes the expectation on
    ///      that harmless getter instead of on the call under test. Every
    ///      revert test in this file silently passed nothing until this was
    ///      hoisted out.
    uint256 internal oneUsdc;

    event BountyOpened(
        uint256 indexed bountyId,
        address indexed sponsor,
        address indexed target,
        address checker,
        bytes4 selector,
        uint256 reward,
        string functionSignature
    );

    function setUp() public {
        registry = new BountyRegistry();
        vault = new DemoVault();
        checker = new VaultChecker(IVaultLedger(address(vault)));
        oneUsdc = registry.ONE_USDC();

        vm.deal(sponsor, 1_000 * oneUsdc);
        vm.deal(otherSponsor, 1_000 * oneUsdc);
        vm.deal(stranger, 1_000 * oneUsdc);
    }

    function _open(address who, uint256 reward) internal returns (uint256 id) {
        vm.prank(who);
        id = registry.openBounty{value: reward}(address(vault), checker, SIG);
    }

    // ---------------------------------------------------------------------
    // 1. Opening a bounty
    // ---------------------------------------------------------------------

    function test_OpenBountyEscrowsFundsAndRecordsDetails() public {
        uint256 reward = 10 * oneUsdc;

        uint256 id = _open(sponsor, reward);

        assertEq(id, 0, "first bounty should be id 0");
        assertEq(address(registry).balance, reward, "funds must land in the registry");
        assertEq(registry.totalEscrowed(), reward, "escrow accounting must match");
        assertEq(registry.bountyCount(), 1);

        BountyRegistry.Bounty memory b = registry.getBounty(id);
        assertEq(b.sponsor, sponsor);
        assertEq(b.target, address(vault));
        assertEq(address(b.checker), address(checker));
        assertEq(b.reward, reward);
        assertEq(b.functionSignature, SIG);
        assertFalse(b.paid, "nothing is paid in v0.3.0");
        assertEq(b.selector, bytes4(keccak256(bytes(SIG))), "selector must derive from signature");
    }

    function test_SelectorMatchesWhatAnAgentWouldCompute() public {
        uint256 id = _open(sponsor, oneUsdc);
        BountyRegistry.Bounty memory b = registry.getBounty(id);

        // This is the number an agent needs to build calldata for the target.
        assertEq(b.selector, DemoVault.deposit.selector, "must match the real function");
    }

    function test_OpenBountyEmitsEverythingAnIndexerNeeds() public {
        uint256 reward = 3 * oneUsdc;

        vm.expectEmit(true, true, true, true, address(registry));
        emit BountyOpened(
            0, sponsor, address(vault), address(checker), bytes4(keccak256(bytes(SIG))), reward, SIG
        );

        vm.prank(sponsor);
        registry.openBounty{value: reward}(address(vault), checker, SIG);
    }

    // ---------------------------------------------------------------------
    // 2. Bounties must not touch each other's money
    // ---------------------------------------------------------------------

    function test_TwoBountiesKeepSeparateBooks() public {
        DemoVault otherVault = new DemoVault();
        VaultChecker otherChecker = new VaultChecker(IVaultLedger(address(otherVault)));

        uint256 rewardA = 7 * oneUsdc;
        uint256 rewardB = 2 * oneUsdc;

        uint256 idA = _open(sponsor, rewardA);

        vm.prank(otherSponsor);
        uint256 idB =
            registry.openBounty{value: rewardB}(address(otherVault), otherChecker, "withdraw(uint256)");

        BountyRegistry.Bounty memory a = registry.getBounty(idA);
        BountyRegistry.Bounty memory b = registry.getBounty(idB);

        assertEq(a.reward, rewardA, "A must keep its own reward");
        assertEq(b.reward, rewardB, "B must keep its own reward");
        assertEq(a.sponsor, sponsor);
        assertEq(b.sponsor, otherSponsor);
        assertEq(a.target, address(vault));
        assertEq(b.target, address(otherVault));
        assertTrue(a.selector != b.selector, "different signatures, different selectors");

        assertEq(registry.totalEscrowed(), rewardA + rewardB);
        assertEq(address(registry).balance, rewardA + rewardB, "no leakage between bounties");
    }

    function testFuzz_EscrowAlwaysEqualsTheSumOfRewards(uint96[5] memory rewards) public {
        uint256 expected;

        for (uint256 i = 0; i < rewards.length; ++i) {
            uint256 reward = uint256(rewards[i]);
            if (reward == 0) continue; // zero funding is rejected; tested separately

            DemoVault v = new DemoVault();
            VaultChecker c = new VaultChecker(IVaultLedger(address(v)));

            vm.deal(sponsor, reward);
            vm.prank(sponsor);
            registry.openBounty{value: reward}(address(v), c, SIG);

            expected += reward;
        }

        assertEq(registry.totalEscrowed(), expected, "escrow must track every deposit");
        assertEq(address(registry).balance, expected, "balance must match the books");
    }

    // ---------------------------------------------------------------------
    // 3. There is no way out for the money
    // ---------------------------------------------------------------------

    /**
     * @notice Probes the contract for any escape hatch reachable by call.
     * @dev Complements `scripts/verify-no-withdrawal.sh`, which checks the same
     *      claim against the compiled ABI. This half proves that unknown
     *      selectors are not swallowed by a fallback and that the balance is
     *      unmoved by anything a caller can reach.
     */
    function test_NoWithdrawalPathExists() public {
        uint256 reward = 25 * oneUsdc;
        _open(sponsor, reward);
        assertEq(address(registry).balance, reward);

        string[12] memory attempts = [
            "withdraw()",
            "withdraw(uint256)",
            "withdrawAll()",
            "emergencyWithdraw()",
            "sweep()",
            "sweep(address)",
            "rescue(address,uint256)",
            "kill()",
            "selfdestruct()",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)"
        ];

        for (uint256 i = 0; i < attempts.length; ++i) {
            // Try as the sponsor, the most privileged party there could be.
            vm.prank(sponsor);
            (bool ok,) =
                address(registry).call(abi.encodeWithSelector(bytes4(keccak256(bytes(attempts[i])))));
            assertFalse(ok, string.concat("reachable escape hatch: ", attempts[i]));
        }

        // No receive/fallback either, so value cannot even be parked here.
        vm.prank(stranger);
        (bool sent,) = address(registry).call{value: 1 ether}("");
        assertFalse(sent, "registry must reject bare value transfers");

        assertEq(address(registry).balance, reward, "balance must be untouched");
        assertEq(registry.totalEscrowed(), reward);
    }

    function test_SponsorHasNoSpecialPowers() public {
        uint256 reward = 5 * oneUsdc;
        uint256 id = _open(sponsor, reward);

        // Being the sponsor is a label in a struct, not a capability. The only
        // thing the sponsor can do that anybody else cannot is nothing at all.
        BountyRegistry.Bounty memory b = registry.getBounty(id);
        assertEq(b.sponsor, sponsor);

        uint256 sponsorBalanceBefore = sponsor.balance;
        vm.prank(sponsor);
        (bool ok,) = address(registry).call(abi.encodeWithSignature("withdraw(uint256)", id));
        assertFalse(ok);
        assertEq(sponsor.balance, sponsorBalanceBefore, "sponsor cannot recover a penny");
    }

    // ---------------------------------------------------------------------
    // 4. Rejections — every one of these would create dead money
    // ---------------------------------------------------------------------

    function test_OpeningWithoutFundingReverts() public {
        vm.prank(sponsor);
        vm.expectRevert(BountyRegistry.EmptyBounty.selector);
        registry.openBounty{value: 0}(address(vault), checker, SIG);

        assertEq(registry.bountyCount(), 0, "nothing should be recorded");
    }

    function test_CheckerBoundToADifferentTargetIsRejected() public {
        // The vulnerability this task exists to close: declare vault A, supply
        // a checker welded to vault B. Agents attack A, the checker watches B,
        // and the bounty can never be claimed while still looking funded.
        DemoVault decoyTarget = new DemoVault();

        vm.prank(sponsor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BountyRegistry.CheckerTargetMismatch.selector, address(decoyTarget), address(vault)
            )
        );
        registry.openBounty{value: oneUsdc}(address(decoyTarget), checker, SIG);

        assertEq(registry.bountyCount(), 0);
        assertEq(address(registry).balance, 0, "rejected funding must not stick");
    }

    function test_CheckerWhoseTargetCannotBeReadIsRejected() public {
        TargetRevertingChecker bad = new TargetRevertingChecker();

        vm.prank(sponsor);
        vm.expectRevert(BountyRegistry.CheckerUnusable.selector);
        registry.openBounty{value: oneUsdc}(address(vault), bad, SIG);
    }

    function test_CheckerThatCannotEvaluateIsRejected() public {
        CheckRevertingChecker bad = new CheckRevertingChecker(address(vault));

        vm.prank(sponsor);
        vm.expectRevert(BountyRegistry.CheckerUnusable.selector);
        registry.openBounty{value: oneUsdc}(address(vault), bad, SIG);
    }

    function test_AlreadyBrokenInvariantIsRejected() public {
        // Break the vault first, using its planted boundary bug.
        vault.deposit(vault.LARGE_DEPOSIT_THRESHOLD());
        assertFalse(checker.checkInvariant(), "vault should be broken now");

        vm.prank(sponsor);
        vm.expectRevert(BountyRegistry.InvariantAlreadyBroken.selector);
        registry.openBounty{value: oneUsdc}(address(vault), checker, SIG);
    }

    function test_ZeroTargetIsRejected() public {
        vm.prank(sponsor);
        vm.expectRevert(BountyRegistry.ZeroTarget.selector);
        registry.openBounty{value: oneUsdc}(address(0), checker, SIG);
    }

    function test_ZeroCheckerIsRejected() public {
        vm.prank(sponsor);
        vm.expectRevert(BountyRegistry.ZeroChecker.selector);
        registry.openBounty{value: oneUsdc}(address(vault), IChecker(address(0)), SIG);
    }

    function test_TargetWithoutCodeIsRejected() public {
        address eoa = makeAddr("notAContract");

        vm.prank(sponsor);
        vm.expectRevert(abi.encodeWithSelector(BountyRegistry.TargetNotAContract.selector, eoa));
        registry.openBounty{value: oneUsdc}(eoa, checker, SIG);
    }

    function test_MalformedSignaturesAreRejected() public {
        string[5] memory bad = ["", "deposit", "()", "deposit(uint256", "(uint256)"];

        for (uint256 i = 0; i < bad.length; ++i) {
            vm.prank(sponsor);
            vm.expectRevert(
                abi.encodeWithSelector(BountyRegistry.MalformedFunctionSignature.selector, bad[i])
            );
            registry.openBounty{value: oneUsdc}(address(vault), checker, bad[i]);
        }

        assertEq(registry.bountyCount(), 0);
    }

    function test_ReadingAMissingBountyReverts() public {
        vm.expectRevert(abi.encodeWithSelector(BountyRegistry.NoSuchBounty.selector, uint256(0)));
        registry.getBounty(0);
    }

    // ---------------------------------------------------------------------
    // 5. Units. 1 USDC is 1e18 here, not 1e6.
    // ---------------------------------------------------------------------

    function test_OneUsdcIsOneE18NotOneE6() public view {
        assertEq(registry.ONE_USDC(), 1e18, "Arc native USDC has 18 decimals");
        assertTrue(registry.ONE_USDC() != 1e6, "1e6 would be the ERC-20 convention, not Arc's");
    }

    function test_ARewardOfOneUsdcIsWorthOneUsdc() public {
        uint256 id = _open(sponsor, oneUsdc);

        BountyRegistry.Bounty memory b = registry.getBounty(id);
        assertEq(b.reward, 1e18, "a 1 USDC bounty must escrow 1e18");

        // The mistake this guards against: funding with the 6-decimal figure
        // escrows a trillionth of a dollar and nothing complains.
        assertEq(b.reward / 1e18, 1, "reads as exactly 1 USDC");
        assertEq(uint256(1e6) / 1e18, 0, "1e6 would round to zero USDC");
    }

    function test_RegistryBalanceMatchesTheSumOfEveryDeposit() public {
        uint256[3] memory rewards =
            [oneUsdc, 25 * oneUsdc / 10, 100 * oneUsdc];
        uint256 total;

        for (uint256 i = 0; i < rewards.length; ++i) {
            DemoVault v = new DemoVault();
            VaultChecker c = new VaultChecker(IVaultLedger(address(v)));
            vm.prank(sponsor);
            registry.openBounty{value: rewards[i]}(address(v), c, SIG);
            total += rewards[i];
        }

        (uint256 held, uint256 owed) = registry.escrowStatus();
        assertEq(held, total, "held must equal every USDC ever sent in");
        assertEq(owed, total, "owed must equal held while nothing is paid");
        assertEq(held, 103.5 ether, "1 + 2.5 + 100 USDC at 18 decimals");
    }

    // ---------------------------------------------------------------------
    // 6. An agent can find work without being told anything
    // ---------------------------------------------------------------------

    function test_OpenBountiesAreEnumerableByAnybody() public {
        DemoVault v2 = new DemoVault();
        VaultChecker c2 = new VaultChecker(IVaultLedger(address(v2)));

        _open(sponsor, 4 * oneUsdc);
        vm.prank(otherSponsor);
        registry.openBounty{value: 6 * oneUsdc}(address(v2), c2, "withdraw(uint256)");

        // A complete stranger, holding no privileges, reads the whole board.
        vm.prank(stranger);
        uint256[] memory ids = registry.openBountyIds();
        assertEq(ids.length, 2);
        assertEq(ids[0], 0);
        assertEq(ids[1], 1);

        vm.prank(stranger);
        BountyRegistry.Bounty[] memory list = registry.openBounties();
        assertEq(list.length, 2);
        assertEq(list[0].functionSignature, SIG);
        assertEq(list[1].functionSignature, "withdraw(uint256)");
        assertEq(list[1].reward, 6 * oneUsdc);

        // Everything needed to build an attack is in that one response.
        assertEq(list[1].target, address(v2));
        assertEq(address(list[1].checker), address(c2));
        assertEq(list[1].selector, bytes4(keccak256(bytes("withdraw(uint256)"))));
    }

    function test_EnumerationIsEmptyBeforeAnyBountyExists() public view {
        assertEq(registry.openBountyIds().length, 0);
        assertEq(registry.openBounties().length, 0);
        assertEq(registry.bountyCount(), 0);
    }
}
