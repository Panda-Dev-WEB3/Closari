// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IExchangeCalendar} from "./interfaces/IExchangeCalendar.sol";
import {IMarketFactory} from "./interfaces/IMarketFactory.sol";

/// @notice Explicit UTC sessions per ET trading day, published by the timelock (Backend §3.1).
///         DST is resolved off-chain (packages/core/src/calendar/nyse.ts); this contract only checks shape.
contract ExchangeCalendar is IExchangeCalendar {
    uint64 internal constant NORMAL_SESSION = 23_400; // 09:30–16:00
    uint64 internal constant EARLY_SESSION = 12_600; // 09:30–13:00
    uint64 internal constant DAY = 86_400;

    address public immutable timelock;
    /// @dev Predicted at deploy (nonce-based); its hasMarkets() locks a listed day.
    IMarketFactory public immutable factory;

    mapping(uint32 => Session) internal _sessions;

    constructor(address timelock_, address factory_) {
        timelock = timelock_;
        factory = IMarketFactory(factory_);
    }

    function setSessions(uint32[] calldata dayIds, Session[] calldata sessions) external {
        if (msg.sender != timelock) revert NotTimelock();
        if (dayIds.length != sessions.length) revert LengthMismatch();
        for (uint256 i; i < dayIds.length; ++i) {
            uint32 d = dayIds[i];
            Session calldata s = sessions[i];
            if (factory.hasMarkets(d)) revert DayLocked(d);
            if (s.closeTs == 0) {
                if (s.openTs != 0) revert BadSession(d);
            } else {
                if (s.openTs >= s.closeTs) revert BadSession(d);
                uint64 len = s.closeTs - s.openTs;
                if (len != NORMAL_SESSION && len != EARLY_SESSION) revert BadSession(d);
                uint64 start = uint64(d) * DAY;
                if (s.openTs < start || s.closeTs >= start + DAY) revert BadSession(d);
            }
            _sessions[d] = s;
            emit SessionSet(d, s.openTs, s.closeTs);
        }
    }

    function session(uint32 dayId) external view returns (Session memory) {
        return _sessions[dayId];
    }

    function isTradingDay(uint32 dayId) external view returns (bool) {
        return _sessions[dayId].closeTs != 0;
    }

    function prevTradingDay(uint32 dayId, uint32 maxLookback) external view returns (uint32) {
        for (uint32 i = 1; i <= maxLookback && i <= dayId; ++i) {
            uint32 d = dayId - i;
            if (_sessions[d].closeTs != 0) return d;
        }
        return 0;
    }
}
