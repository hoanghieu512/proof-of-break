// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {DemoVault} from "../src/DemoVault.sol";

/**
 * @notice Experiment, not a guard: can Foundry's own fuzzer reach the planted
 *         boundary bug unaided?
 *
 *         This matters for how the project is allowed to describe itself.
 *         Foundry's fuzzer is not uniform random — it seeds its dictionary
 *         from constants found in the code under test, so a threshold declared
 *         as a public constant may be handed to it for free. If it finds the
 *         bug easily, then "an agent beats random fuzzing" is the wrong claim
 *         and the honest framing is different.
 *
 *         Deliberately NOT part of the normal suite's guarantees — its result
 *         depends on the fuzz seed. Run it explicitly:
 *
 *           forge test --match-contract FuzzerReach --fuzz-runs 20000
 */
contract FuzzerReachTest is Test {
    DemoVault internal vault;
    uint256 internal threshold;

    function setUp() public {
        vault = new DemoVault();
        threshold = vault.LARGE_DEPOSIT_THRESHOLD();
    }

    /// @dev Fails if and only if the fuzzer manages to submit exactly the
    ///      threshold. A failure here is the interesting outcome, which is why
    ///      this is skipped unless asked for: a test that is *supposed* to fail
    ///      has no business making the suite red on every run.
    ///
    ///      Measured 2026-08-01 at 20,000 runs: found the boundary on seed 1
    ///      after 305 runs, seed 2 after 92, seed 3 after 28.
    ///
    ///        POB_RUN_FUZZ_REACH=true forge test --match-contract FuzzerReach \
    ///          --fuzz-runs 20000 --fuzz-seed 1
    function testFuzz_CanTheFuzzerReachTheBoundary(uint256 amount) public {
        vm.skip(!vm.envOr("POB_RUN_FUZZ_REACH", false));

        amount = bound(amount, 1, type(uint128).max);
        vault.deposit(amount);
        assertEq(
            vault.sumOfBalances(),
            vault.totalIssued(),
            "fuzzer reached the boundary value"
        );
    }
}
