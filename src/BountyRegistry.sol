// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IChecker} from "./IChecker.sol";

/**
 * @title BountyRegistry
 * @notice The only contract in Proof-of-Break that holds money.
 *
 *         A sponsor opens a bounty by declaring a target contract, a checker
 *         that tests an invariant of that target, and the one function an agent
 *         is allowed to fire at it — funding the whole thing with native USDC
 *         in the same transaction. Anyone can read the open bounties.
 *
 * @dev v0.3.0 covers opening and escrow only. The attack-and-payout mechanism
 *      is Task 4 and is deliberately absent here.
 *
 *      THERE IS NO WAY TO WITHDRAW FROM THIS CONTRACT.
 *
 *      Not for the sponsor, not for the author, not for anybody. There is no
 *      withdrawal function, no admin key, no owner, no pause and no upgrade
 *      path, and no `receive`/`fallback` through which stray value could
 *      arrive. Money leaves by exactly one route: the payout in `attempt`, to
 *      whoever just proved a break, in the same transaction that proved it.
 *      This is the transparency claim in design doc §8.
 *
 *      `scripts/verify-escrow.sh` checks the statically checkable half against
 *      the compiled artefact and runs the tests that pin the rest.
 *
 *      UNITS — THE EASIEST THING TO GET WRONG HERE
 *
 *      Arc's native USDC has 18 decimals, confirmed by transaction on Day 1
 *      (docs/measurements/day1-report.md), not the 6 decimals that the ERC-20
 *      form of USDC uses everywhere else. So:
 *
 *          1 USDC == 1e18 wei, NOT 1e6
 *
 *      Funding a bounty with `1e6` would escrow one trillionth of a dollar, and
 *      nothing would fail: no revert, no failing test, just a bounty worth
 *      nothing. `ONE_USDC` exists so that number is written down once.
 */
contract BountyRegistry {
    /**
     * @notice One USDC in the units this contract deals in.
     * @dev Arc's native gas token is USDC with 18 decimals. See the note above
     *      before assuming this should be 1e6.
     */
    uint256 public constant ONE_USDC = 1e18;

    struct Bounty {
        /// @notice Who funded it. Recorded for attribution only — it grants no
        ///         powers whatsoever, including the power to get the money back.
        address sponsor;
        /// @notice The contract under test.
        address target;
        /// @notice The checker that judges the invariant. Verified at open time
        ///         to be bound to `target`.
        IChecker checker;
        /// @notice Selector of the single function an agent may fire, derived
        ///         from `functionSignature`.
        bytes4 selector;
        /// @notice USDC escrowed for this bounty, in 18-decimal units.
        uint256 reward;
        /// @notice Set by the payout logic in Task 4. Always false in v0.3.0.
        bool paid;
        /// @notice Human-readable signature, e.g. "deposit(uint256)". An agent
        ///         reads this to learn what argument types to generate, which
        ///         is what lets it attack a target it knew nothing about
        ///         (design doc §7.5).
        string functionSignature;
    }

    Bounty[] private _bounties;

    /**
     * @notice Total USDC currently owed across all unpaid bounties.
     * @dev The internal invariant this contract is meant to satisfy is
     *      `address(this).balance >= totalEscrowed`, with equality unless
     *      somebody forces value in. Task 4 will assert it under fuzzing; here
     *      it is already tracked so the property exists from the start
     *      (design doc §9).
     */
    uint256 public totalEscrowed;

    /**
     * @dev Reentrancy lock. One lock for the whole contract, not one per
     *      function: `attempt` hands control to an arbitrary target while this
     *      contract is holding every bounty's money, and that target must be
     *      unable to re-enter *anything* — not just `attempt`, but `openBounty`
     *      too. Per-function guards would leave that door open.
     *
     *      1/2 rather than false/true so the slot is never zero, which keeps
     *      each lock/unlock a warm SSTORE instead of paying the 20,000 gas
     *      zero-to-nonzero price on every call.
     */
    uint256 private constant _UNLOCKED = 1;
    uint256 private constant _LOCKED = 2;
    uint256 private _lock = _UNLOCKED;

    modifier nonReentrant() {
        if (_lock == _LOCKED) revert ReentrantCall();
        _lock = _LOCKED;
        _;
        _lock = _UNLOCKED;
    }

    event BountyOpened(
        uint256 indexed bountyId,
        address indexed sponsor,
        address indexed target,
        address checker,
        bytes4 selector,
        uint256 reward,
        string functionSignature
    );

    /// @notice Emitted for every attempt that ran to completion, broken or not.
    ///         The record of what an agent tried is public either way.
    event AttemptMade(uint256 indexed bountyId, address indexed attacker, bool brokeInvariant);

    /// @notice Emitted when a bounty is paid. The only event that accompanies
    ///         value leaving this contract.
    event BountyClaimed(uint256 indexed bountyId, address indexed claimant, uint256 reward);

    error EmptyBounty();
    error ZeroTarget();
    error ZeroChecker();
    error TargetNotAContract(address target);
    error CheckerTargetMismatch(address declaredTarget, address checkerTarget);
    error CheckerUnusable();
    error InvariantAlreadyBroken();
    error MalformedFunctionSignature(string functionSignature);
    error NoSuchBounty(uint256 bountyId);
    error SelfReference();
    error ReentrantCall();
    error BountyAlreadyPaid(uint256 bountyId);
    error CallDataTooShort();
    error DisallowedFunction(bytes4 attempted, bytes4 allowed);
    error TargetCallFailed();
    error PayoutFailed();

    /**
     * @notice Open and fund a bounty. The USDC sent with this call is escrowed.
     * @param target_ The contract an agent will be allowed to attack.
     * @param checker_ A checker bound to `target_` that judges one invariant.
     * @param functionSignature The one function agents may call, written the
     *        way Solidity writes it, e.g. "deposit(uint256)".
     * @return bountyId Index of the new bounty, stable for the contract's life.
     *
     * @dev Every rejection below exists to stop a bounty that could never be
     *      claimed. That matters more here than it would elsewhere: with no
     *      withdrawal function, an unclaimable bounty is not an inconvenience,
     *      it is money destroyed.
     */
    function openBounty(address target_, IChecker checker_, string calldata functionSignature)
        external
        payable
        nonReentrant
        returns (uint256 bountyId)
    {
        if (msg.value == 0) revert EmptyBounty();
        if (target_ == address(0)) revert ZeroTarget();
        if (address(checker_) == address(0)) revert ZeroChecker();
        // Naming this contract as the target would let an agent aim arbitrary
        // calldata at the escrow itself through `attempt`. The reentrancy lock
        // already blocks it, but refusing it at the door is cheaper to reason
        // about than relying on a second line of defence.
        if (target_ == address(this) || address(checker_) == address(this)) revert SelfReference();
        if (target_.code.length == 0) revert TargetNotAContract(target_);
        if (!_isWellFormedSignature(functionSignature)) {
            revert MalformedFunctionSignature(functionSignature);
        }

        // THE CHECK THIS TASK EXISTS FOR.
        //
        // A checker is welded to its target when it is deployed, so a sponsor
        // can declare target A while supplying a checker that watches target B.
        // Agents would then hammer A while the checker calmly reports on B,
        // whose invariant never moves. Nobody could ever be paid, and the
        // sponsor would still get credit for advertising a funded bounty.
        //
        // Asking the checker which contract it actually watches costs one
        // staticcall and closes it.
        try checker_.target() returns (address checkerTarget) {
            if (checkerTarget != target_) {
                revert CheckerTargetMismatch(target_, checkerTarget);
            }
        } catch {
            revert CheckerUnusable();
        }

        // A bounty over an already-broken invariant can never be claimed: the
        // payout in Task 4 requires a true -> false transition to prove the
        // agent's action caused the break (design doc §6). Opening one would
        // burn the sponsor's money on arrival.
        try checker_.checkInvariant() returns (bool holds) {
            if (!holds) revert InvariantAlreadyBroken();
        } catch {
            revert CheckerUnusable();
        }

        bountyId = _bounties.length;
        totalEscrowed += msg.value;

        _bounties.push(
            Bounty({
                sponsor: msg.sender,
                target: target_,
                checker: checker_,
                selector: bytes4(keccak256(bytes(functionSignature))),
                reward: msg.value,
                paid: false,
                functionSignature: functionSignature
            })
        );

        Bounty storage b = _bounties[bountyId];
        emit BountyOpened(
            bountyId, msg.sender, target_, address(checker_), b.selector, msg.value, functionSignature
        );
    }

    /**
     * @notice Fire one action at a bounty's target and collect the reward if
     *         that action breaks the invariant.
     *
     * @param bountyId Which bounty to attack.
     * @param callData Full calldata for the target, selector first. The
     *        selector must be the one the bounty declared; anything else is
     *        refused before the call is made.
     * @return brokeInvariant True if the reward was paid to the caller.
     *
     * @dev THE ATOMIC SEQUENCE (design doc §6)
     *
     *        1. ask the checker whether the invariant holds
     *        2. perform the agent's action on the target
     *        3. ask the checker again
     *
     *      A true -> false transition inside a single transaction is what
     *      proves the action *caused* the break, and pays the person who found
     *      it rather than the first person to notice it. There is no moment
     *      between the break and the payout for anyone else to step into, so
     *      there is nothing to front-run.
     *
     *      WHY A CHECKER THAT CANNOT ANSWER IS FATAL, NOT PERMISSIVE
     *
     *      Step 3 must produce a definite `false` to pay. If the checker
     *      reverts, or runs out of gas, or is otherwise unable to answer, this
     *      function reverts. Treating "could not answer" as "invariant broken"
     *      would hand an attacker a payout for merely making the checker fail —
     *      which, since the target's own action runs first, is something a
     *      hostile target could arrange. Silence is never taken as proof.
     *
     *      ORDERING
     *
     *      The bounty is marked paid and removed from the escrow total before
     *      any value moves, and the whole function is behind the contract-wide
     *      reentrancy lock. The payout amount is read from storage and is
     *      always exactly this bounty's reward, so no attempt can reach another
     *      bounty's money even if everything else went wrong.
     */
    function attempt(uint256 bountyId, bytes calldata callData)
        external
        nonReentrant
        returns (bool brokeInvariant)
    {
        if (bountyId >= _bounties.length) revert NoSuchBounty(bountyId);
        Bounty storage b = _bounties[bountyId];
        if (b.paid) revert BountyAlreadyPaid(bountyId);

        // Only the declared function may be called. Checked before the target
        // is touched, so a rejected attempt costs the target nothing.
        if (callData.length < 4) revert CallDataTooShort();
        bytes4 selector = bytes4(callData[:4]);
        if (selector != b.selector) revert DisallowedFunction(selector, b.selector);

        IChecker checker = b.checker;

        // Step 1. Refuse to start from a broken state: a break that was already
        // there proves nothing about the action about to be taken.
        if (!_mustAnswer(checker)) revert InvariantAlreadyBroken();

        // Step 2. The agent's action. Arbitrary code at an arbitrary address —
        // the single most dangerous line in this project.
        if (!_callTarget(b.target, callData)) revert TargetCallFailed();

        // Step 3. Ask again. Anything other than a definite answer reverts.
        brokeInvariant = !_mustAnswer(checker);

        emit AttemptMade(bountyId, msg.sender, brokeInvariant);
        if (!brokeInvariant) return false;

        // Effects before interactions.
        uint256 reward = b.reward;
        b.paid = true;
        totalEscrowed -= reward;

        emit BountyClaimed(bountyId, msg.sender, reward);

        (bool sent,) = msg.sender.call{value: reward}("");
        if (!sent) revert PayoutFailed();

        return true;
    }

    /**
     * @dev Asks the checker and insists on a real answer.
     * @return holds The checker's verdict.
     *
     *      Reverts with `CheckerUnusable` if the checker cannot answer. Note
     *      the asymmetry that matters: a failure here becomes a revert, never a
     *      `false`. See the note on `attempt` for why that direction is the
     *      only safe one.
     */
    function _mustAnswer(IChecker checker) private view returns (bool holds) {
        try checker.checkInvariant() returns (bool result) {
            return result;
        } catch {
            revert CheckerUnusable();
        }
    }

    /**
     * @dev Calls the target with the agent's calldata, forwarding no value and
     *      copying no return data.
     *
     *      Written in assembly for one specific reason: Solidity's `.call`
     *      copies the callee's return data into memory, so a hostile target can
     *      return megabytes and make the memory expansion cost explode. That
     *      only burns the agent's gas rather than the escrow, but there is no
     *      reason to accept it when the return value is not wanted. Passing
     *      (0, 0) as the output area discards it at the EVM level.
     *
     *      Value is hard-coded to 0. This contract never sends money to a
     *      target — the only value transfer in the whole contract is the payout
     *      in `attempt`.
     */
    function _callTarget(address target_, bytes calldata callData) private returns (bool ok) {
        assembly ("memory-safe") {
            // Scratch space above the free memory pointer. Nothing is expected
            // to survive this call, so the pointer is deliberately not moved.
            let ptr := mload(0x40)
            calldatacopy(ptr, callData.offset, callData.length)
            ok := call(gas(), target_, 0, ptr, callData.length, 0, 0)
        }
    }

    // -----------------------------------------------------------------------
    // Read-only surface. Everything below is how an agent finds work.
    // -----------------------------------------------------------------------

    /// @notice How many bounties have ever been opened, paid or not.
    function bountyCount() external view returns (uint256) {
        return _bounties.length;
    }

    /// @notice Full record of one bounty.
    function getBounty(uint256 bountyId) external view returns (Bounty memory) {
        if (bountyId >= _bounties.length) revert NoSuchBounty(bountyId);
        return _bounties[bountyId];
    }

    /**
     * @notice Ids of every bounty still available to claim.
     * @dev The entry point for an autonomous agent: read this, pick one, read
     *      its `functionSignature` and `checker`, and decide whether to attack
     *      it. Nothing here is gated on who is asking.
     *
     *      O(n) over all bounties ever opened, which is fine for an off-chain
     *      `eth_call` and would not be if this were ever called on-chain.
     */
    function openBountyIds() external view returns (uint256[] memory ids) {
        uint256 n = _bounties.length;
        uint256 count;
        for (uint256 i = 0; i < n; ++i) {
            if (!_bounties[i].paid) ++count;
        }

        ids = new uint256[](count);
        uint256 j;
        for (uint256 i = 0; i < n; ++i) {
            if (!_bounties[i].paid) {
                ids[j] = i;
                ++j;
            }
        }
    }

    /// @notice Every unpaid bounty in full, for agents that would rather make
    ///         one call than n+1.
    function openBounties() external view returns (Bounty[] memory list) {
        uint256 n = _bounties.length;
        uint256 count;
        for (uint256 i = 0; i < n; ++i) {
            if (!_bounties[i].paid) ++count;
        }

        list = new Bounty[](count);
        uint256 j;
        for (uint256 i = 0; i < n; ++i) {
            if (!_bounties[i].paid) {
                list[j] = _bounties[i];
                ++j;
            }
        }
    }

    /**
     * @notice The escrow property, exposed so anyone can verify it from outside.
     * @return held Actual USDC sitting in this contract.
     * @return owed Sum of all unpaid bounty rewards.
     * @dev `held < owed` would mean the contract cannot cover its obligations
     *      and must never happen.
     */
    function escrowStatus() external view returns (uint256 held, uint256 owed) {
        return (address(this).balance, totalEscrowed);
    }

    /**
     * @dev Cheap sanity check on a function signature. A signature that does
     *      not parse produces a selector matching nothing, so the bounty could
     *      never be claimed and — with no withdrawal — its funding would be
     *      lost. This does not validate argument types; it only rejects strings
     *      that are obviously not signatures.
     */
    function _isWellFormedSignature(string calldata signature) private pure returns (bool) {
        bytes calldata s = bytes(signature);
        // Shortest possible signature is "f()".
        if (s.length < 3) return false;
        if (s[s.length - 1] != CLOSE_PAREN) return false;
        // An opening paren must exist and must not be the first character,
        // otherwise there is no function name.
        for (uint256 i = 1; i < s.length - 1; ++i) {
            if (s[i] == OPEN_PAREN) return true;
        }
        return false;
    }

    bytes1 private constant OPEN_PAREN = hex"28"; // '('
    bytes1 private constant CLOSE_PAREN = hex"29"; // ')'
}
