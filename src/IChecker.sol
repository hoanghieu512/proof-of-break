// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IChecker
 * @notice The one thing every checker in Proof-of-Break must be able to do:
 *         answer whether a declared invariant still holds.
 *
 * @dev WHY THIS INTERFACE IS SHAPED LIKE THIS
 *
 *      `checkInvariant()` takes no arguments. That is deliberate, and it is the
 *      security property of the whole arrangement:
 *
 *        - A checker is bound to its target when it is deployed. Nothing the
 *          caller passes in can redirect it at a different contract or feed it
 *          a fabricated view of the world. There is no argument to poison.
 *        - The Registry therefore needs to know nothing whatsoever about the
 *          target or the property being tested. It calls one function and gets
 *          one boolean. That is what lets anybody open a bounty on anybody
 *          else's contract (design doc §7.1).
 *
 *      `checkInvariant()` is declared `view`. This is not a promise, it is
 *      enforcement: Solidity compiles a call to a `view` function into the EVM's
 *      STATICCALL, and STATICCALL makes any state write inside that call frame
 *      revert at the machine level. A hostile checker cannot write storage, emit
 *      logs, or send value during the check even if its author wanted it to.
 *
 *      WHAT THIS INTERFACE DOES NOT PROTECT AGAINST
 *
 *      A checker author can still write a `checkInvariant()` that always returns
 *      true, so the bounty can never be claimed while looking like it could be
 *      (design doc §9, "Checker gian"). Nothing here prevents that. The defence
 *      is that checker source is verified and public, so an agent can read it
 *      before spending gas — which is why `description()` and `target()` are
 *      part of the interface rather than left optional.
 *
 *      A checker can also revert, or burn every gas unit it is given. The
 *      Registry is the component that has to survive that, and it is Task 4's
 *      problem, not this interface's.
 */
interface IChecker {
    /**
     * @notice Does the invariant still hold right now?
     * @return holds True if the property is intact, false if it has been broken.
     * @dev The Registry calls this twice in one transaction — once before the
     *      agent's action and once after — and pays out only on a true→false
     *      transition, which is what proves the action caused the break
     *      (design doc §6).
     */
    function checkInvariant() external view returns (bool holds);

    /**
     * @notice The contract whose state this checker reads.
     * @dev Lets an agent confirm that a bounty's declared target and its
     *      checker's actual target are the same contract, instead of taking
     *      the bounty's word for it.
     */
    function target() external view returns (address);

    /**
     * @notice Plain-language statement of the property being checked.
     * @dev Exists so a human reviewing the bounty on a block explorer, and an
     *      agent deciding whether the bounty is worth attacking, can both read
     *      what is actually being claimed.
     */
    function description() external view returns (string memory);
}
