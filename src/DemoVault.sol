// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title DemoVault
 * @notice A ledger-only vault: it records who is owed how many units and how
 *         many units it has issued in total. It never moves real tokens —
 *         everything here is bookkeeping (design doc §7.5).
 *
 * @dev ┌──────────────────────────────────────────────────────────────────┐
 *      │  THIS CONTRACT CONTAINS A DELIBERATE BUG.                        │
 *      │                                                                  │
 *      │  It is the practice target for Proof-of-Break — a shooting-range │
 *      │  contract that an autonomous agent is supposed to break in order │
 *      │  to claim a bounty. The flaw is planted on purpose and is        │
 *      │  documented in full below. It is not an oversight, and it is not │
 *      │  hidden: this repository is public and the honesty is part of    │
 *      │  the submission.                                                 │
 *      │                                                                  │
 *      │  DO NOT COPY THIS PATTERN INTO ANYTHING REAL.                    │
 *      └──────────────────────────────────────────────────────────────────┘
 *
 *      THE INVARIANT THIS VAULT IS SUPPOSED TO UPHOLD
 *
 *        sum(balanceOf[h] for every holder h) == totalIssued
 *
 *      Every unit credited to somebody must also be counted as issued. If the
 *      two sides drift apart, the vault's books are lying about how much it
 *      owes. That is a real class of bug, and it is the property VaultChecker
 *      (Task 2) will test.
 *
 *      WHERE THE BUG IS
 *
 *      `deposit` pays a 1% loyalty bonus on large deposits. Two lines decide
 *      what counts as "large", and they disagree by one comparison operator:
 *
 *        - the bonus is granted when   amount >= LARGE_DEPOSIT_THRESHOLD
 *        - totalIssued counts it when  amount >  LARGE_DEPOSIT_THRESHOLD
 *
 *      For amount <  threshold : no bonus, both sides add `amount`.      OK
 *      For amount >  threshold : bonus paid, both sides add `credited`.  OK
 *      For amount == threshold : bonus is paid into the holder's balance,
 *                                but totalIssued only counts `amount`.   BROKEN
 *
 *      So the books go out by exactly the bonus — 1% of the threshold — and
 *      they do it at exactly one input value out of 2^256. A single call to
 *      `deposit(LARGE_DEPOSIT_THRESHOLD)` breaks the invariant from a clean
 *      deployment; no setup and no second transaction are needed.
 *
 *      WHY THIS PARTICULAR BUG
 *
 *      An off-by-one between `>` and `>=` on a threshold is the most ordinary
 *      boundary defect there is, which is the point (design doc §7.3). Random
 *      fuzzing has to guess one exact 256-bit value and effectively never will.
 *      Boundary value analysis tries the threshold itself on the first pass and
 *      lands it immediately. That gap is the argument the demo is built to
 *      show, and `test/DemoVault.t.sol` measures it rather than asserting it.
 */
contract DemoVault {
    /// @notice Units credited to each account. Public, so any checker can read
    ///         a single holder's balance without this contract's cooperation.
    mapping(address => uint256) public balanceOf;

    /// @notice Units the vault believes it has issued in total. This is the
    ///         figure that is supposed to match the sum of all balances.
    uint256 public totalIssued;

    /// @dev A Solidity mapping cannot be iterated — there is no way to ask it
    ///      for its keys. So every address that has ever held a balance is
    ///      recorded here too, otherwise no checker could ever sum the balances.
    address[] private _holders;
    mapping(address => bool) private _isHolder;

    /// @notice Deposits at or above this size earn a loyalty bonus.
    /// @dev 1e18 is one whole unit at 18 decimals, matching Arc's native USDC.
    ///      It is `public` on purpose: an agent should be able to read the
    ///      threshold off-chain and put it in its boundary list.
    uint256 public constant LARGE_DEPOSIT_THRESHOLD = 1e18;

    /// @notice Loyalty bonus in basis points. 100 bps = 1%.
    uint256 public constant BONUS_BPS = 100;

    uint256 private constant BPS_DENOMINATOR = 10_000;

    event Deposited(address indexed account, uint256 amount, uint256 bonus);
    event Withdrawn(address indexed account, uint256 amount);

    error ZeroAmount();
    error InsufficientBalance(uint256 requested, uint256 available);

    /**
     * @notice Credit `amount` units to the caller, plus a loyalty bonus if the
     *         deposit is large enough.
     * @dev Solidity 0.8 reverts on arithmetic overflow, so an absurdly large
     *      `amount` fails loudly rather than wrapping around silently.
     */
    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        // Bonus is granted at or above the threshold.
        uint256 bonus =
            amount >= LARGE_DEPOSIT_THRESHOLD ? (amount * BONUS_BPS) / BPS_DENOMINATOR : 0;

        uint256 credited = amount + bonus;

        _registerHolder(msg.sender);
        balanceOf[msg.sender] += credited;

        // THE PLANTED BUG. This must mirror the condition above, and does not:
        // it uses `>` where the bonus used `>=`. At amount == threshold the
        // bonus lands in the balance but is never counted as issued.
        totalIssued += amount > LARGE_DEPOSIT_THRESHOLD ? credited : amount;

        emit Deposited(msg.sender, amount, bonus);
    }

    /**
     * @notice Burn `amount` units from the caller's balance.
     * @dev Correct on both sides — the bug is confined to `deposit` so that the
     *      demo has exactly one thing to find.
     */
    function withdraw(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        uint256 available = balanceOf[msg.sender];
        if (amount > available) revert InsufficientBalance(amount, available);

        balanceOf[msg.sender] = available - amount;
        totalIssued -= amount;

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice How many addresses have ever held a balance here.
    function holderCount() external view returns (uint256) {
        return _holders.length;
    }

    /// @notice The holder at `index`. Paired with `holderCount`, this lets a
    ///         checker walk every balance without trusting any aggregate.
    function holderAt(uint256 index) external view returns (address) {
        return _holders[index];
    }

    /// @notice The full holder list in one call.
    function holders() external view returns (address[] memory) {
        return _holders;
    }

    /**
     * @notice Convenience aggregate of every balance.
     * @dev Offered for tests and for cheap off-chain reads. A checker guarding
     *      real money should NOT trust this — it is computed by the contract
     *      under test, which is exactly the party that might be lying. Task 2's
     *      VaultChecker walks `holderAt` itself for that reason.
     */
    function sumOfBalances() external view returns (uint256 total) {
        uint256 n = _holders.length;
        for (uint256 i = 0; i < n; ++i) {
            total += balanceOf[_holders[i]];
        }
    }

    function _registerHolder(address account) private {
        if (!_isHolder[account]) {
            _isHolder[account] = true;
            _holders.push(account);
        }
    }
}
