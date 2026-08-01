// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {KillGateProbe} from "../src/KillGateProbe.sol";

/// @notice Proves the Foundry toolchain itself works: compile, deploy in EVM,
///         call, assert, and fuzz. Not product coverage.
contract KillGateProbeTest is Test {
    KillGateProbe internal probe;

    event ValueSet(address indexed setter, uint256 previousValue, uint256 newValue);

    function setUp() public {
        probe = new KillGateProbe(42);
    }

    function test_ConstructorSetsInitialState() public view {
        assertEq(probe.value(), 42, "initial value not stored");
        assertEq(probe.deployer(), address(this), "deployer not recorded");
        assertEq(probe.bumps(), 0, "bumps should start at zero");
    }

    function test_SetValueWritesAndReadsBack() public {
        probe.setValue(123);
        assertEq(probe.value(), 123, "value not written");
    }

    function test_SetValueEmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(probe));
        emit ValueSet(address(this), 42, 7);
        probe.setValue(7);
    }

    function test_BumpIncrements() public {
        probe.bump();
        probe.bump();
        assertEq(probe.bumps(), 2, "bumps not counted");
    }

    /// @dev Fuzzing works out of the box — this is the capability the whole
    ///      project rests on, so prove it on Day 1 rather than assuming it.
    function testFuzz_SetValueRoundTrips(uint256 newValue) public {
        probe.setValue(newValue);
        assertEq(probe.value(), newValue, "fuzz round-trip failed");
    }
}
