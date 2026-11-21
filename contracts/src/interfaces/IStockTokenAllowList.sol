// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @notice Genuine-token check plus the timelocked token → feed mapping (Backend §3.2).
interface IStockTokenAllowList {
    struct Asset {
        bytes32 pythId; // Pyth regular-session feed id (share terms)
        address clFeed; // Chainlink proxy (token terms, already multiplier-scaled)
        uint32 tickPrice8; // strike rounding tick, e.g. 50_000_000 = $0.50
        uint96 budgetAbove; // per-market budget, USDG base units
        uint96 budgetRange;
        uint96 budgetUpDown;
        bool listed;
    }

    event AssetSet(address indexed token, Asset asset);

    error NotTimelock();
    error NotGenuine(address token);
    error BadAsset();
    error BadFeedDecimals(uint8 decimals);

    /// @dev token.codehash == PROXY_CODEHASH (the 283-byte proxy embeds the beacon) and the beacon has an implementation.
    function isGenuine(address token) external view returns (bool);
    /// @notice onlyTimelock; reverts unless isGenuine(token), pythId != 0, tickPrice8 != 0 and clFeed.decimals() == 8.
    function setAsset(address token, Asset calldata a) external;
    function asset(address token) external view returns (Asset memory);
}
