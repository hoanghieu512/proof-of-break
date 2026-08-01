// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {DemoVault} from "../src/DemoVault.sol";
import {IChecker} from "../src/IChecker.sol";
import {VaultChecker, IVaultLedger} from "../src/VaultChecker.sol";

/**
 * @notice A ledger that keeps honest primitive state but lies in its summary.
 * @dev Models the threat the checker exists to resist: the contract under test
 *      is the party with a motive to misreport. Per-holder balances and
 *      totalIssued are truthful — they have to be, other contracts depend on
 *      them — but `sumOfBalances()` always parrots `totalIssued`, so anything
 *      that trusts the summary concludes the books balance perfectly.
 */
contract LyingVault is IVaultLedger {
    uint256 public totalIssued;
    mapping(address => uint256) public balanceOf;
    address[] private _holders;

    function credit(address who, uint256 amount) external {
        if (balanceOf[who] == 0) _holders.push(who);
        balanceOf[who] += amount;
    }

    function setTotalIssued(uint256 value) external {
        totalIssued = value;
    }

    function holderCount() external view returns (uint256) {
        return _holders.length;
    }

    function holderAt(uint256 index) external view returns (address) {
        return _holders[index];
    }

    /// @notice The lie: always reports a total that makes the vault look sound.
    function sumOfBalances() external view returns (uint256) {
        return totalIssued;
    }
}

contract VaultCheckerTest is Test {
    DemoVault internal vault;
    VaultChecker internal checker;

    uint256 internal threshold;
    uint256 internal expectedDrift;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vault = new DemoVault();
        checker = new VaultChecker(IVaultLedger(address(vault)));
        threshold = vault.LARGE_DEPOSIT_THRESHOLD();
        expectedDrift = (threshold * vault.BONUS_BPS()) / 10_000;
    }

    // ---------------------------------------------------------------------
    // 1. The two answers that matter
    // ---------------------------------------------------------------------

    function test_HealthyVaultReportsInvariantHolding() public {
        assertTrue(checker.checkInvariant(), "empty vault should be sound");

        vm.prank(alice);
        vault.deposit(0.5 ether);
        assertTrue(checker.checkInvariant(), "ordinary deposit should stay sound");

        vm.prank(bob);
        vault.deposit(5 ether); // above threshold, bonus paid and counted
        assertTrue(checker.checkInvariant(), "large deposit should stay sound");

        vm.prank(bob);
        vault.withdraw(1 ether);
        assertTrue(checker.checkInvariant(), "withdrawal should stay sound");
    }

    function test_BoundaryBugMakesCheckerReportViolation() public {
        assertTrue(checker.checkInvariant(), "should start sound");

        vm.prank(alice);
        vault.deposit(threshold); // the planted boundary bug

        assertFalse(checker.checkInvariant(), "checker must catch the drift");

        (uint256 excessCredited, uint256 excessIssued) = checker.drift();
        assertEq(excessCredited, expectedDrift, "drift should equal the uncounted bonus");
        assertEq(excessIssued, 0, "drift is in the credited direction");

        emit log_named_uint("unbacked units credited", excessCredited);
    }

    function test_TransitionIsExactlyWhatTheRegistryWillLookFor() public {
        // Design doc §6: pay out only on a true -> false transition inside one
        // transaction. Rehearse that sequence here without the Registry.
        bool before = checker.checkInvariant();

        vm.prank(alice);
        vault.deposit(threshold);

        bool afterwards = checker.checkInvariant();

        assertTrue(before, "invariant must hold before the action");
        assertFalse(afterwards, "invariant must be broken after the action");
    }

    function test_HarmlessActionProducesNoTransition() public {
        bool before = checker.checkInvariant();
        vm.prank(alice);
        vault.deposit(threshold - 1); // one below the boundary
        bool afterwards = checker.checkInvariant();

        assertTrue(before);
        assertTrue(afterwards, "a near-miss must not look like a break");
    }

    // ---------------------------------------------------------------------
    // 2. The target is not trusted
    // ---------------------------------------------------------------------

    function test_ReportsCorrectlyWhenTheTargetLies() public {
        LyingVault liar = new LyingVault();
        VaultChecker honestChecker = new VaultChecker(IVaultLedger(address(liar)));

        // Books are genuinely broken: 150 units credited, 100 declared issued.
        liar.credit(alice, 100);
        liar.credit(bob, 50);
        liar.setTotalIssued(100);

        // A checker that trusted the target's own summary would be satisfied.
        bool naiveVerdict = liar.sumOfBalances() == liar.totalIssued();
        assertTrue(naiveVerdict, "the lie should be convincing to a naive checker");

        // Ours recomputes from per-holder state and is not fooled.
        assertFalse(honestChecker.checkInvariant(), "checker must not trust the summary");
        assertEq(honestChecker.recomputedTotal(), 150, "should derive the real total");

        (uint256 excessCredited,) = honestChecker.drift();
        assertEq(excessCredited, 50);
    }

    function test_TargetCannotBeRedirectedByCaller() public view {
        // There is no argument to poison — the target is fixed at deployment.
        assertEq(checker.target(), address(vault));
        assertEq(address(checker.vault()), address(vault));
    }

    function test_ConstructorRejectsZeroTarget() public {
        vm.expectRevert(VaultChecker.ZeroTarget.selector);
        new VaultChecker(IVaultLedger(address(0)));
    }

    // ---------------------------------------------------------------------
    // 3. The checker cannot write state
    // ---------------------------------------------------------------------

    /**
     * @notice Proves read-onlyness at the EVM level, not by inspection.
     * @dev STATICCALL makes any storage write, log, or value transfer inside
     *      the call frame revert. If `checkInvariant` succeeds under STATICCALL,
     *      it provably performed none of them. This is the same call opcode the
     *      Registry will use, because the interface declares the function `view`.
     */
    function test_CheckInvariantSucceedsUnderStaticcall() public {
        vm.prank(alice);
        vault.deposit(threshold);

        (bool ok, bytes memory ret) =
            address(checker).staticcall(abi.encodeCall(IChecker.checkInvariant, ()));

        assertTrue(ok, "checkInvariant must survive STATICCALL");
        assertFalse(abi.decode(ret, (bool)), "and still return the right answer");
    }

    function test_AllReadPathsSurviveStaticcall() public view {
        (bool a,) = address(checker).staticcall(abi.encodeCall(IChecker.target, ()));
        (bool b,) = address(checker).staticcall(abi.encodeCall(IChecker.description, ()));
        (bool c,) = address(checker).staticcall(abi.encodeCall(VaultChecker.drift, ()));
        (bool d,) = address(checker).staticcall(abi.encodeCall(VaultChecker.recomputedTotal, ()));
        assertTrue(a && b && c && d, "every checker entry point must be read-only");
    }

    function test_ImplementsTheInterface() public view {
        IChecker asInterface = IChecker(address(checker));
        assertEq(asInterface.target(), address(vault));
        assertGt(bytes(asInterface.description()).length, 0, "description must not be empty");
    }

    // ---------------------------------------------------------------------
    // 4. Correct for arbitrary ledger states
    // ---------------------------------------------------------------------

    function testFuzz_AgreesWithAnIndependentSum(uint96 a, uint96 b, uint96 issued) public {
        vm.assume(a > 0 && b > 0);

        LyingVault ledger = new LyingVault();
        ledger.credit(alice, a);
        ledger.credit(bob, b);
        ledger.setTotalIssued(issued);

        VaultChecker c = new VaultChecker(IVaultLedger(address(ledger)));

        uint256 realSum = uint256(a) + uint256(b);
        assertEq(c.recomputedTotal(), realSum, "recomputed total must be exact");
        assertEq(c.checkInvariant(), realSum == issued, "verdict must match reality");
    }

    // ---------------------------------------------------------------------
    // 5. The gas ceiling this design has
    // ---------------------------------------------------------------------

    /**
     * @notice Measures how the check scales, and states where it stops fitting.
     * @dev The Registry calls the checker twice per claim attempt, so the
     *      budget that matters is 2x this number plus the target call and the
     *      Registry's own overhead. Arc's block gas limit is 30,000,000
     *      (measured on chain, 2026-08-01).
     */
    function test_GasScalesLinearlyWithHolders() public {
        uint256[6] memory sizes = [uint256(1), 10, 50, 100, 250, 500];
        uint256[6] memory costs; // first (cold) call
        uint256[6] memory pairCosts; // both calls, as the Registry will make them

        for (uint256 s = 0; s < sizes.length; ++s) {
            DemoVault v = _vaultWithHolders(sizes[s]);
            VaultChecker c = new VaultChecker(IVaultLedger(address(v)));

            // Without this the measurement is a lie. Those balance slots were
            // written moments ago in this same execution context, so they are
            // "warm" and cost 100 gas to read. In a real claim transaction the
            // Registry touches them for the first time and pays the cold price
            // of 2,100 each (EIP-2929). vm.cool resets the account and its
            // slots to cold so the number reflects the transaction that will
            // actually be sent.
            vm.cool(address(v));

            uint256 before = gasleft();
            c.checkInvariant();
            costs[s] = before - gasleft();

            // The Registry's second call re-reads the very same slots, which
            // the first call has now warmed. Doubling the cold figure would
            // overstate the real cost, so measure the actual pair instead.
            uint256 beforeWarm = gasleft();
            c.checkInvariant();
            uint256 warmCost = beforeWarm - gasleft();
            pairCosts[s] = costs[s] + warmCost;

            emit log_named_uint(
                string.concat("cold check @ ", vm.toString(sizes[s]), " holders"), costs[s]
            );
            emit log_named_uint(
                string.concat("cold+warm pair @ ", vm.toString(sizes[s]), " holders"), pairCosts[s]
            );
        }

        // Marginal cost per holder, taken across the widest span measured.
        uint256 marginalCold = (costs[5] - costs[3]) / (sizes[5] - sizes[3]);
        uint256 marginalPair = (pairCosts[5] - pairCosts[3]) / (sizes[5] - sizes[3]);
        emit log_named_uint("marginal gas/holder, cold check", marginalCold);
        emit log_named_uint("marginal gas/holder, check pair", marginalPair);

        uint256 blockGasLimit = 30_000_000;
        emit log_named_uint("holders where the pair fills a block", blockGasLimit / marginalPair);
        emit log_named_uint("practical ceiling (half a block)    ", blockGasLimit / marginalPair / 2);

        assertGt(costs[5], costs[0], "cost must grow with holder count");
        assertGt(marginalCold, 0, "marginal cost must be measurable");
        assertLt(
            marginalPair,
            2 * marginalCold,
            "the second check should be cheaper than the first; slots are warm by then"
        );
    }

    function _vaultWithHolders(uint256 n) internal returns (DemoVault v) {
        v = new DemoVault();
        for (uint256 i = 0; i < n; ++i) {
            // casting to 'uint160' is safe because i is bounded by the largest
            // size measured (500), so the value never exceeds 0x101F3
            // forge-lint: disable-next-line(unsafe-typecast)
            address holder = address(uint160(0x10000 + i));
            vm.prank(holder);
            // Deliberately away from the boundary so these vaults stay sound.
            v.deposit(0.1 ether + i);
        }
    }
}
