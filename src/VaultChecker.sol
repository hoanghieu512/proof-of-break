// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IChecker} from "./IChecker.sol";

/**
 * @title IVaultLedger
 * @notice The minimal read surface VaultChecker needs from a ledger contract.
 * @dev The checker depends on this rather than on DemoVault directly. Two
 *      reasons: it works with any contract exposing the same public getters
 *      (which is the claim in design doc §7.1), and it keeps the checker from
 *      accidentally reaching for a convenience aggregate it must not trust.
 *
 *      Note what is deliberately absent: `sumOfBalances()`. DemoVault offers
 *      one, and this checker refuses to know about it. See below.
 */
interface IVaultLedger {
    function totalIssued() external view returns (uint256);
    function holderCount() external view returns (uint256);
    function holderAt(uint256 index) external view returns (address);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title VaultChecker
 * @notice Tests one property of a ledger vault:
 *
 *           sum of every holder's balance == totalIssued
 *
 *         Every unit credited to somebody must also be counted as issued. When
 *         the two drift apart, the vault's books are claiming an amount of
 *         backing that does not exist.
 *
 * @dev WHY THIS RECOMPUTES THE SUM INSTEAD OF ASKING FOR IT
 *
 *      DemoVault exposes `sumOfBalances()`, which would make this checker a
 *      one-liner. Using it would be a serious mistake. The target is the
 *      contract under suspicion — it is precisely the party with a motive to
 *      misreport, whether through a bug or on purpose. A checker that asks the
 *      suspect to summarise its own books is not checking anything.
 *
 *      So this walks `holderAt(i)` and reads each `balanceOf` individually,
 *      deriving the total from the same primitive state a human auditor would
 *      read off a block explorer. `test_ReportsCorrectlyWhenTheTargetLies`
 *      demonstrates the difference against a target that reports a flattering
 *      total.
 *
 *      KNOWN LIMITATION — GAS GROWS WITH HOLDER COUNT
 *
 *      The loop costs one external call and one cold storage read per holder,
 *      and the Registry calls this twice per claim attempt. That cost is linear
 *      in the number of holders and it is charged to the agent trying to claim.
 *      Past enough holders, a claim transaction cannot fit in a block and the
 *      bounty becomes unclaimable even though the bug is real and was found.
 *
 *      Measured figures and the estimated ceiling are in
 *      `docs/measurements/task2-checker-gas.md`; the test
 *      `test_GasScalesLinearlyWithHolders` regenerates them.
 *
 *      This is NOT solved in v1. The honest scope is a demo target with a
 *      handful of holders. A production version would need the invariant
 *      restated in a form that is O(1) to verify — for example having the
 *      vault maintain a running sum that the checker compares against
 *      `totalIssued` in constant time, which moves the cost to deposit-time
 *      and off the claim path.
 */
contract VaultChecker is IChecker {
    /// @notice The ledger this checker observes. Fixed at deployment so no
    ///         caller can point it somewhere else.
    IVaultLedger public immutable vault;

    error ZeroTarget();

    constructor(IVaultLedger vault_) {
        if (address(vault_) == address(0)) revert ZeroTarget();
        vault = vault_;
    }

    /// @inheritdoc IChecker
    function target() external view returns (address) {
        return address(vault);
    }

    /// @inheritdoc IChecker
    function description() external pure returns (string memory) {
        return "sum of balanceOf(holderAt(i)) for all i in [0, holderCount) == totalIssued";
    }

    /**
     * @inheritdoc IChecker
     * @dev Arithmetic here is checked, so a sum that overflows reverts rather
     *      than wrapping to a small number and reporting a healthy vault. A
     *      revert is a refusal to answer, which is safe; a wrapped total would
     *      be a confident wrong answer, which is not.
     */
    function checkInvariant() external view returns (bool holds) {
        return _sumOfBalances() == vault.totalIssued();
    }

    /**
     * @notice How far the books are out, and in which direction.
     * @return excessCredited Units credited to holders but never counted as
     *         issued. Non-zero means the vault owes more than it admits.
     * @return excessIssued Units counted as issued but credited to nobody.
     * @dev Not part of IChecker — the Registry only needs the boolean. This
     *      exists so a claim can be reported with a number attached rather than
     *      just "something is wrong", which matters for evidence and for the
     *      demo. Exactly one of the two returns is non-zero when broken.
     */
    function drift() external view returns (uint256 excessCredited, uint256 excessIssued) {
        uint256 credited = _sumOfBalances();
        uint256 issued = vault.totalIssued();
        if (credited > issued) {
            excessCredited = credited - issued;
        } else {
            excessIssued = issued - credited;
        }
    }

    /// @notice The recomputed total, exposed for inspection and testing.
    function recomputedTotal() external view returns (uint256) {
        return _sumOfBalances();
    }

    function _sumOfBalances() private view returns (uint256 total) {
        uint256 n = vault.holderCount();
        for (uint256 i = 0; i < n; ++i) {
            total += vault.balanceOf(vault.holderAt(i));
        }
    }
}
