// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {SettlementOracle} from "../../src/SettlementOracle.sol";
import {IMarketFactory} from "../../src/interfaces/IMarketFactory.sol";

/// @notice Fork-test access to the oracle's Chainlink round location and Pyth parse. Never deployed.
contract SettlementOracleHarness is SettlementOracle {
    constructor(address pyth_) SettlementOracle(pyth_, address(1), address(1), address(1)) {}

    function locate(address feed, uint80 rid, uint64 closeTs)
        external
        view
        returns (bool ok, bool fresh, int256 answer, uint256 updatedAt, uint80 used)
    {
        return _locate(feed, rid, closeTs);
    }

    function parseUnique(bytes32 id, uint256 snapshotWad, uint64 lo, uint64 hi, bytes[] calldata upd)
        external
        payable
        returns (int64 p, uint64 c, uint64 pt, uint8 v)
    {
        IMarketFactory.DayInfo memory d;
        d.pythId = id;
        d.multiplierSnapshot = snapshotWad;
        Px memory x = _price(d, upd, lo, hi);
        return (x.p, x.c, x.pt, uint8(x.v));
    }
}
