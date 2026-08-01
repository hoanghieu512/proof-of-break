// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BountyRegistry} from "../../src/BountyRegistry.sol";
import {IChecker} from "../../src/IChecker.sol";

/**
 * @notice Contracts written specifically to attack BountyRegistry.
 * @dev These exist to be pointed at the escrow. Every one of them models a way
 *      a sponsor or an agent could try to turn `attempt` against the money it
 *      is guarding. If any of them ever succeeds, the project is unshippable.
 */

/// @notice A target that flips a public flag, so a checker can judge it.
///         The honest baseline the hostile variants are built from.
contract FlagTarget {
    bool public broken;

    function poke(uint256) external virtual {
        broken = true;
    }

    function harmless(uint256) external pure {}
}

/// @notice Reports the invariant as "the target's flag is still down".
contract FlagChecker is IChecker {
    address private immutable _target;

    constructor(address target_) {
        _target = target_;
    }

    function checkInvariant() external view returns (bool) {
        return !FlagTarget(_target).broken();
    }

    function target() external view returns (address) {
        return _target;
    }

    function description() external pure returns (string memory) {
        return "FlagTarget.broken() == false";
    }
}

/**
 * @notice A target that calls back into the Registry while the Registry is
 *         mid-attempt and holding every bounty's money.
 * @dev The classic drain shape. It swallows the failure so the outer attempt
 *      still completes, which lets a test assert both that the re-entry was
 *      refused and that the outer flow behaved normally.
 */
contract ReentrantTarget is FlagTarget {
    enum Mode {
        None,
        ReenterAttempt,
        ReenterOpenBounty
    }

    BountyRegistry public immutable registry;
    Mode public mode;
    uint256 public victimBountyId;
    bool public reentryWasBlocked;
    bytes public reentryRevertData;

    constructor(BountyRegistry registry_) {
        registry = registry_;
    }

    function configure(Mode mode_, uint256 victimBountyId_) external {
        mode = mode_;
        victimBountyId = victimBountyId_;
    }

    receive() external payable {}

    function poke(uint256 value) external override {
        if (mode == Mode.ReenterAttempt) {
            try registry.attempt(victimBountyId, abi.encodeWithSignature("poke(uint256)", value))
            returns (bool) {
                // Reaching here means the lock failed to hold.
            } catch (bytes memory reason) {
                reentryWasBlocked = true;
                reentryRevertData = reason;
            }
        } else if (mode == Mode.ReenterOpenBounty) {
            // Args are deliberately junk: the reentrancy modifier runs before
            // any argument validation, so a blocked call must revert on the
            // lock rather than on the arguments.
            try registry.openBounty{value: 1}(address(this), IChecker(address(this)), "poke(uint256)")
            returns (uint256) {
                // Reaching here means the lock failed to hold.
            } catch (bytes memory reason) {
                reentryWasBlocked = true;
                reentryRevertData = reason;
            }
        }

        broken = true;
    }
}

/**
 * @notice A checker that answers honestly until sabotaged, then cannot answer.
 * @dev Models the sharpest attack on the three-step sequence: let the "before"
 *      check pass, then break the checker during the action so the "after"
 *      check fails. If the Registry read a failed check as "invariant broken",
 *      this would mint a payout out of nothing.
 */
contract SabotageChecker is IChecker {
    enum Sabotage {
        None,
        Revert,
        BurnGas
    }

    address private immutable _target;
    Sabotage public sabotage;

    constructor(address target_) {
        _target = target_;
    }

    function setSabotage(Sabotage mode_) external {
        sabotage = mode_;
    }

    function checkInvariant() external view returns (bool) {
        if (sabotage == Sabotage.Revert) {
            revert("checker sabotaged");
        }
        if (sabotage == Sabotage.BurnGas) {
            uint256 x;
            // Large enough to exhaust anything it is given.
            for (uint256 i = 0; i < 1e9; ++i) {
                x = uint256(keccak256(abi.encode(x, i)));
            }
            return x == 0;
        }
        return true;
    }

    function target() external view returns (address) {
        return _target;
    }

    function description() external pure returns (string memory) {
        return "always true until sabotaged";
    }
}

/// @notice A target whose action disables its own checker.
contract CheckerSabotagingTarget {
    SabotageChecker public checker;
    SabotageChecker.Sabotage public mode;

    function configure(SabotageChecker checker_, SabotageChecker.Sabotage mode_) external {
        checker = checker_;
        mode = mode_;
    }

    function poke(uint256) external {
        checker.setSabotage(mode);
    }
}

/**
 * @notice A target that returns an enormous amount of data.
 * @dev If the Registry copied return data into memory, this would inflate the
 *      cost of every attempt. The Registry discards it at the EVM level.
 */
contract ReturndataBombTarget is FlagTarget {
    function poke(uint256) external override {
        broken = true;
        assembly {
            // 64 KiB of zeroes handed back to the caller.
            return(0, 0x10000)
        }
    }
}

/// @notice A claimant that refuses its reward, so the payout call fails.
contract RejectingClaimant {
    BountyRegistry public immutable registry;

    constructor(BountyRegistry registry_) {
        registry = registry_;
    }

    function attempt(uint256 bountyId, bytes calldata callData) external returns (bool) {
        return registry.attempt(bountyId, callData);
    }

    // No receive(), no fallback() — value sent here reverts.
}
