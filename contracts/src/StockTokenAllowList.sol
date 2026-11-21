// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IStockTokenAllowList} from "./interfaces/IStockTokenAllowList.sol";
import {IBeacon} from "./interfaces/external/IBeacon.sol";
import {AggregatorV3Interface} from "@chainlink/AggregatorV3Interface.sol";

/// @notice Two-part listing check (Backend §3.2): the token is a genuine beacon proxy (codehash; the proxy embeds
///         the beacon as an immutable), and the timelock maps it to its feeds. The beacon's implementation may be
///         upgraded by the issuer; Closari pins the beacon, not the implementation.
contract StockTokenAllowList is IStockTokenAllowList {
    address public immutable BEACON;
    bytes32 public immutable PROXY_CODEHASH;
    address public immutable timelock;

    mapping(address => Asset) internal _assets;

    constructor(address beacon, bytes32 proxyCodehash, address timelock_) {
        BEACON = beacon;
        PROXY_CODEHASH = proxyCodehash;
        timelock = timelock_;
    }

    function isGenuine(address token) public view returns (bool) {
        if (token.code.length == 0 || token.codehash != PROXY_CODEHASH) return false;
        try IBeacon(BEACON).implementation() returns (address impl) {
            return impl != address(0);
        } catch {
            return false;
        }
    }

    function setAsset(address token, Asset calldata a) external {
        if (msg.sender != timelock) revert NotTimelock();
        if (!isGenuine(token)) revert NotGenuine(token);
        if (a.pythId == bytes32(0) || a.tickPrice8 == 0) revert BadAsset();
        uint8 d = AggregatorV3Interface(a.clFeed).decimals();
        if (d != 8) revert BadFeedDecimals(d);
        _assets[token] = a;
        emit AssetSet(token, a);
    }

    function asset(address token) external view returns (Asset memory) {
        return _assets[token];
    }
}
