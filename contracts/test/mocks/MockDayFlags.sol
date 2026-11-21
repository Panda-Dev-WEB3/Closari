// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @notice Stands in for the factory's hasMarkets() in calendar unit tests.
contract MockDayFlags {
    mapping(uint32 => bool) public hasMarkets;

    function set(uint32 dayId, bool v) external {
        hasMarkets[dayId] = v;
    }
}
