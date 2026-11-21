// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @notice ERC-8056 subset exposed by Robinhood Chain stock tokens (advisory, read on the token).
interface IStockToken {
    function uiMultiplier() external view returns (uint256);
    function newUIMultiplier() external view returns (uint256);
    function effectiveAt() external view returns (uint256);
    function oraclePaused() external view returns (bool);
}
