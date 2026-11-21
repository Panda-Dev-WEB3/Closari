// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @notice ERC-8056 surface. No immutables, so every deployment shares one codehash (the "genuine" proxy shape).
contract MockStockToken {
    uint256 public uiMultiplier;
    uint256 public newUIMultiplier;
    uint256 public effectiveAt;
    bool public oraclePaused;

    constructor(uint256 multiplier) {
        uiMultiplier = multiplier;
        newUIMultiplier = multiplier;
    }

    function setMultiplier(uint256 m) external {
        uiMultiplier = m;
        newUIMultiplier = m;
    }

    function schedule(uint256 m, uint256 at) external {
        newUIMultiplier = m;
        effectiveAt = at;
    }

    function setOraclePaused(bool p) external {
        oraclePaused = p;
    }
}

/// @notice Same surface, different bytecode: must never pass isGenuine.
contract MockStockTokenLookalike is MockStockToken {
    constructor(uint256 multiplier) MockStockToken(multiplier) {}

    function lookalike() external pure returns (bool) {
        return true;
    }
}
