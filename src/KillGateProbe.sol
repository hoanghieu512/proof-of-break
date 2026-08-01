// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title KillGateProbe
/// @notice Day-1 environment probe. This is NOT product code and carries no
///         Proof-of-Break logic. Its only job is to prove that the full path
///         compile -> deploy -> write state -> read state back works on Arc
///         Testnet, and to give the RPC burst test a cheap state-changing call.
/// @dev Safe to delete once BountyRegistry lands.
contract KillGateProbe {
    /// @notice Last value written. `public` makes solc generate a free getter.
    uint256 public value;

    /// @notice Who deployed this. `immutable` is baked into bytecode, not storage.
    address public immutable deployer;

    /// @notice Counts `bump()` calls. Used as the RPC burst workload.
    uint256 public bumps;

    event ValueSet(address indexed setter, uint256 previousValue, uint256 newValue);
    event Bumped(address indexed caller, uint256 bumps);

    constructor(uint256 initialValue) {
        deployer = msg.sender;
        value = initialValue;
        emit ValueSet(msg.sender, 0, initialValue);
    }

    /// @notice Write state. Proves a state-changing call reaches the chain.
    function setValue(uint256 newValue) external {
        uint256 previousValue = value;
        value = newValue;
        emit ValueSet(msg.sender, previousValue, newValue);
    }

    /// @notice Cheapest useful state write: one non-zero-to-non-zero SSTORE.
    ///         Used to measure sustained RPC throughput and per-tx gas cost.
    function bump() external {
        unchecked {
            ++bumps;
        }
        emit Bumped(msg.sender, bumps);
    }
}
