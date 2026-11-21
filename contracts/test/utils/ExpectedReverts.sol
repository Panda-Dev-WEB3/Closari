// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ILMSRMarket} from "../../src/interfaces/ILMSRMarket.sol";

/// @dev True for the revert reasons a legitimate trade attempt may hit under the property suites' call patterns.
/// Panics (including the market's own I1′ `assert`) and every other error are NOT expected.
function isExpectedTradeRevert(bytes memory err) pure returns (bool) {
    if (err.length < 4) return false;
    bytes4 sel;
    assembly {
        sel := mload(add(err, 32))
    }
    return sel == ILMSRMarket.PriceOutOfBounds.selector || sel == ILMSRMarket.LateHourCap.selector
        || sel == ILMSRMarket.Halted.selector || sel == ILMSRMarket.CorporateActionVisible.selector
        || sel == ILMSRMarket.TradeTooLarge.selector || sel == ILMSRMarket.InsufficientShares.selector;
}
