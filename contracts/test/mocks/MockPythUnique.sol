// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {MockPyth} from "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/// @notice SDK 4.3.1's MockPyth.parsePriceFeedUpdatesUnique does not check uniqueness (it passes
///         checkUniqueness = false). This forwarder enforces it, as the real Pyth contract does: an update is accepted
///         only if prevPublishTime < minPublishTime (the first update at or after the window start).
contract MockPythUnique {
    MockPyth public immutable inner;

    constructor(MockPyth inner_) {
        inner = inner_;
    }

    function getUpdateFee(bytes[] calldata updateData) external view returns (uint256) {
        return inner.getUpdateFee(updateData);
    }

    function parsePriceFeedUpdates(bytes[] calldata u, bytes32[] calldata ids, uint64 lo, uint64 hi)
        external
        payable
        returns (PythStructs.PriceFeed[] memory feeds)
    {
        (feeds,) = inner.parsePriceFeedUpdatesWithConfig{value: msg.value}(u, ids, lo, hi, false, true, false);
    }

    function parsePriceFeedUpdatesUnique(bytes[] calldata u, bytes32[] calldata ids, uint64 lo, uint64 hi)
        external
        payable
        returns (PythStructs.PriceFeed[] memory feeds)
    {
        (feeds,) = inner.parsePriceFeedUpdatesWithConfig{value: msg.value}(u, ids, lo, hi, true, true, false);
    }
}
