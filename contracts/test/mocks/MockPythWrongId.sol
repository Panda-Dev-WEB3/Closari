// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/// @notice A Pyth that answers with the wrong feed id, to exercise the factory's id check.
contract MockPythWrongId {
    bytes32 public immutable returnedId;

    constructor(bytes32 id) {
        returnedId = id;
    }

    function getUpdateFee(bytes[] calldata u) external pure returns (uint256) {
        return u.length;
    }

    function parsePriceFeedUpdates(bytes[] calldata, bytes32[] calldata, uint64, uint64)
        external
        payable
        returns (PythStructs.PriceFeed[] memory feeds)
    {
        feeds = new PythStructs.PriceFeed[](1);
        feeds[0].id = returnedId;
        feeds[0].price = PythStructs.Price({price: 100e8, conf: 0, expo: -8, publishTime: block.timestamp});
        feeds[0].emaPrice = feeds[0].price;
    }
}
