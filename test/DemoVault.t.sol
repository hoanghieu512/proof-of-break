// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {DemoVault} from "../src/DemoVault.sol";

/**
 * @notice Tests for the deliberately broken practice target.
 *
 *         Two things have to be true at once for the demo to mean anything:
 *
 *           1. the vault is CORRECT for ordinary use — otherwise "an agent
 *              found a bug" is not a finding, it is just noise;
 *           2. the vault is BROKEN at exactly one boundary value — and broken
 *              by a measurable amount, not merely "inconsistent".
 *
 *         The last two tests are the ones that carry the argument: random
 *         search does not find this, and boundary value analysis finds it on
 *         the first pass.
 */
contract DemoVaultTest is Test {
    DemoVault internal vault;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal threshold;
    uint256 internal expectedDrift;

    function setUp() public {
        vault = new DemoVault();
        threshold = vault.LARGE_DEPOSIT_THRESHOLD();
        // The books drift by exactly the unpaid bonus: 1% of the threshold.
        expectedDrift = (threshold * vault.BONUS_BPS()) / 10_000;
    }

    /// @dev The property the whole project is built around.
    function _assertLedgerBalanced() internal view {
        assertEq(
            vault.sumOfBalances(),
            vault.totalIssued(),
            "ledger drifted: sum of balances != totalIssued"
        );
    }

    // ---------------------------------------------------------------------
    // 1. Ordinary use must be correct
    // ---------------------------------------------------------------------

    function test_NormalTrafficKeepsTheLedgerBalanced() public {
        vm.prank(alice);
        vault.deposit(0.5 ether);
        _assertLedgerBalanced();

        vm.prank(bob);
        vault.deposit(2 ether); // above threshold: bonus paid and counted
        _assertLedgerBalanced();

        vm.prank(carol);
        vault.deposit(123_456_789);
        _assertLedgerBalanced();

        vm.prank(bob);
        vault.withdraw(1 ether);
        _assertLedgerBalanced();

        vm.prank(alice);
        vault.deposit(0.25 ether);
        _assertLedgerBalanced();

        vm.prank(carol);
        vault.withdraw(123_456_789);
        _assertLedgerBalanced();

        // Read the balance BEFORE pranking: vm.prank only survives one external
        // call, and balanceOf() is itself an external call that would consume it.
        uint256 aliceHolds = vault.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(aliceHolds); // exact full balance
        _assertLedgerBalanced();

        assertEq(vault.balanceOf(alice), 0, "alice should be emptied");
        assertGt(vault.totalIssued(), 0, "bob should still be owed something");
    }

    function test_JustBelowThresholdIsCorrect() public {
        vault.deposit(threshold - 1);
        _assertLedgerBalanced();
        assertEq(vault.balanceOf(address(this)), threshold - 1, "no bonus below threshold");
    }

    function test_JustAboveThresholdIsCorrect() public {
        uint256 amount = threshold + 1;
        vault.deposit(amount);
        _assertLedgerBalanced();
        uint256 bonus = (amount * vault.BONUS_BPS()) / 10_000;
        assertEq(vault.balanceOf(address(this)), amount + bonus, "bonus should be paid above threshold");
    }

    function test_WellAboveThresholdIsCorrect() public {
        vault.deposit(1_000 ether);
        _assertLedgerBalanced();
    }

    // ---------------------------------------------------------------------
    // 2. The boundary value must break it, by a specific number
    // ---------------------------------------------------------------------

    function test_ExactThresholdBreaksTheLedger() public {
        vault.deposit(threshold);

        uint256 balances = vault.sumOfBalances();
        uint256 issued = vault.totalIssued();

        assertEq(balances, threshold + expectedDrift, "balance should include the bonus");
        assertEq(issued, threshold, "totalIssued should have missed the bonus");
        assertEq(balances - issued, expectedDrift, "drift should equal the unpaid bonus");
        assertEq(expectedDrift, 0.01 ether, "1% of 1e18");

        // State the failure in the terms a report would use.
        emit log_named_uint("sum of balances", balances);
        emit log_named_uint("totalIssued    ", issued);
        emit log_named_uint("unbacked units ", balances - issued);
    }

    function test_OneCallFromACleanDeploymentIsEnough() public {
        DemoVault fresh = new DemoVault();

        assertEq(fresh.sumOfBalances(), fresh.totalIssued(), "fresh vault should be balanced");

        fresh.deposit(threshold); // <- the entire exploit

        assertTrue(
            fresh.sumOfBalances() != fresh.totalIssued(),
            "a single call should break the invariant"
        );
    }

    function test_ThresholdBreaksItRegardlessOfWhoCalls() public {
        // The Registry, not the agent, is what the Target sees as msg.sender
        // (design doc §9). The bug must not depend on the caller's identity.
        vm.prank(alice);
        vault.deposit(threshold);
        assertEq(vault.sumOfBalances() - vault.totalIssued(), expectedDrift);
    }

    function test_ThresholdStaysBrokenAfterFurtherNormalUse() public {
        vault.deposit(threshold);
        uint256 drift = vault.sumOfBalances() - vault.totalIssued();

        vm.prank(bob);
        vault.deposit(3 ether);
        vm.prank(bob);
        vault.withdraw(1 ether);

        assertEq(
            vault.sumOfBalances() - vault.totalIssued(),
            drift,
            "drift should persist; normal traffic neither heals nor worsens it"
        );
    }

    // ---------------------------------------------------------------------
    // 3. Input validation
    // ---------------------------------------------------------------------

    function test_ZeroDepositReverts() public {
        vm.expectRevert(DemoVault.ZeroAmount.selector);
        vault.deposit(0);
    }

    function test_ZeroWithdrawReverts() public {
        vm.expectRevert(DemoVault.ZeroAmount.selector);
        vault.withdraw(0);
    }

    function test_OverdrawReverts() public {
        vault.deposit(1_000);
        vm.expectRevert(
            abi.encodeWithSelector(DemoVault.InsufficientBalance.selector, 1_001, 1_000)
        );
        vault.withdraw(1_001);
    }

    function test_HolderListTracksDepositorsOnce() public {
        vm.prank(alice);
        vault.deposit(1_000);
        vm.prank(alice);
        vault.deposit(2_000);
        vm.prank(bob);
        vault.deposit(3_000);

        assertEq(vault.holderCount(), 2, "alice should be recorded once");
        assertEq(vault.holderAt(0), alice);
        assertEq(vault.holderAt(1), bob);
    }

    // ---------------------------------------------------------------------
    // 4. Everything that is not the boundary value is correct
    // ---------------------------------------------------------------------

    /// @dev Bounded below 2^128 so the 1% multiplication cannot overflow —
    ///      an overflow revert is not a ledger bug and would only add noise.
    function testFuzz_EveryOtherAmountKeepsTheLedgerBalanced(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        vm.assume(amount != threshold);

        vault.deposit(amount);
        _assertLedgerBalanced();
    }

    function testFuzz_DepositThenPartialWithdrawStaysBalanced(uint256 amount, uint256 taken)
        public
    {
        amount = bound(amount, 2, type(uint128).max);
        vm.assume(amount != threshold);

        vault.deposit(amount);
        uint256 held = vault.balanceOf(address(this));
        taken = bound(taken, 1, held);

        vault.withdraw(taken);
        _assertLedgerBalanced();
    }

    // ---------------------------------------------------------------------
    // 5. The argument: random search misses, boundary analysis lands
    // ---------------------------------------------------------------------

    /**
     * @notice Random search does not find this bug.
     * @dev The draw is rigged heavily in the random searcher's favour: instead
     *      of the real 2^256 input space it samples [1, 2*threshold], a window
     *      of about 2^61. Even there, 10,000 draws hit the one bad value zero
     *      times. Across the actual input space the chance per draw is 2^-256.
     */
    function test_RandomSearchDoesNotFindTheBug() public view {
        uint256 draws = 10_000;
        uint256 window = 2 * threshold;
        uint256 hits;

        for (uint256 i = 0; i < draws; ++i) {
            uint256 amount = (uint256(keccak256(abi.encode(i, "proof-of-break"))) % window) + 1;
            if (amount == threshold) ++hits;
        }

        assertEq(hits, 0, "random search should not stumble onto the exact threshold");
    }

    /**
     * @notice Boundary value analysis finds it on the first pass.
     * @dev This is the QA claim the project is staking itself on, so it is
     *      measured rather than asserted: run a standard boundary list against
     *      a fresh vault each time, and report how many probes were needed.
     */
    function test_BoundaryValueListFindsItImmediately() public {
        uint256[] memory candidates = _boundaryList();

        uint256 breaks;
        uint256 probesUntilFirstBreak;
        uint256 breakingValue;
        bool found;

        for (uint256 i = 0; i < candidates.length; ++i) {
            DemoVault fresh = new DemoVault();
            try fresh.deposit(candidates[i]) {
                if (fresh.sumOfBalances() != fresh.totalIssued()) {
                    ++breaks;
                    if (!found) {
                        found = true;
                        probesUntilFirstBreak = i + 1;
                        breakingValue = candidates[i];
                    }
                }
            } catch {
                // Rejected input (zero, or an amount that overflows the bonus
                // maths). A revert is not a broken invariant.
            }
        }

        assertTrue(found, "boundary list should find the bug");
        assertEq(breaks, 1, "exactly one boundary value should break it");
        assertEq(breakingValue, threshold, "the breaking value should be the threshold itself");

        emit log_named_uint("boundary candidates tried", candidates.length);
        emit log_named_uint("probes until first break ", probesUntilFirstBreak);
    }

    /**
     * @dev A standard boundary list for a uint256 amount with one known
     *      threshold. Nothing here is tailored to the planted bug — these are
     *      the values any tester would try against a function that takes a
     *      quantity and branches on a limit.
     */
    function _boundaryList() internal view returns (uint256[] memory list) {
        list = new uint256[](16);
        uint256 i;

        // degenerate values
        list[i++] = 0;
        list[i++] = 1;
        list[i++] = 2;

        // around the declared threshold
        list[i++] = threshold - 2;
        list[i++] = threshold - 1;
        list[i++] = threshold;
        list[i++] = threshold + 1;
        list[i++] = threshold + 2;
        list[i++] = threshold * 2;
        list[i++] = threshold / 2;

        // machine-word boundaries
        list[i++] = type(uint8).max;
        list[i++] = type(uint16).max;
        list[i++] = type(uint32).max;
        list[i++] = type(uint64).max;
        list[i++] = type(uint128).max;
        list[i++] = type(uint256).max;
    }
}
