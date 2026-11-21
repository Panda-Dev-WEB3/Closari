// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ISettlementOracle} from "../../src/interfaces/ISettlementOracle.sol";

contract MockSettlementOracle {
    mapping(address => mapping(uint32 => ISettlementOracle.PriceResult)) internal _close;

    function setCloseResult(address token, uint32 dayId, ISettlementOracle.PriceResult calldata r) external {
        _close[token][dayId] = r;
    }

    function closeResult(address token, uint32 dayId) external view returns (ISettlementOracle.PriceResult memory) {
        return _close[token][dayId];
    }
}
