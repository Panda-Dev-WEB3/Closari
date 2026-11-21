// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @notice Explicit UTC sessions per ET trading day (Backend §3.1). A day with no session is closed.
interface IExchangeCalendar {
    struct Session {
        uint64 openTs; // UTC seconds
        uint64 closeTs; // UTC seconds; 0 => closed
    }

    event SessionSet(uint32 indexed dayId, uint64 openTs, uint64 closeTs);

    error NotTimelock();
    error LengthMismatch();
    error BadSession(uint32 dayId);
    error DayLocked(uint32 dayId);

    /// @notice onlyTimelock. openTs < closeTs; closeTs - openTs in {12_600, 23_400}; both inside dayId's UTC day;
    ///         (0,0) clears a day. Reverts for a day that already has markets.
    function setSessions(uint32[] calldata dayIds, Session[] calldata sessions) external;

    function session(uint32 dayId) external view returns (Session memory);
    function isTradingDay(uint32 dayId) external view returns (bool);
    /// @return The closest earlier day with a session within maxLookback days, or 0.
    function prevTradingDay(uint32 dayId, uint32 maxLookback) external view returns (uint32);
}
