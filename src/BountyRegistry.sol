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
 *      THERE IS NO WAY TO TAKE MONEY OUT OF THIS CONTRACT.
 *
 *      Not for the sponsor, not for the author, not for anybody. There is no
 *      withdrawal function, no admin key, no owner, no pause, no upgrade path,
 *      and no `receive`/`fallback`. Once USDC is escrowed against a bounty the
 *      only thing that will ever move it is the payout logic in Task 4, and
 *      that pays whoever proves the break. This is the transparency claim in
 *      design doc §8, and it is the reason to state it as a property of the
 *      bytecode rather than a promise in a README.
 *
 *      `scripts/verify-no-withdrawal.sh` asserts it against the compiled ABI.
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

    event BountyOpened(
        uint256 indexed bountyId,
        address indexed sponsor,
        address indexed target,
        address checker,
        bytes4 selector,
        uint256 reward,
        string functionSignature
    );

    error EmptyBounty();
    error ZeroTarget();
    error ZeroChecker();
    error TargetNotAContract(address target);
    error CheckerTargetMismatch(address declaredTarget, address checkerTarget);
    error CheckerUnusable();
    error InvariantAlreadyBroken();
    error MalformedFunctionSignature(string functionSignature);
    error NoSuchBounty(uint256 bountyId);

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
        returns (uint256 bountyId)
    {
        if (msg.value == 0) revert EmptyBounty();
        if (target_ == address(0)) revert ZeroTarget();
        if (address(checker_) == address(0)) revert ZeroChecker();
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
