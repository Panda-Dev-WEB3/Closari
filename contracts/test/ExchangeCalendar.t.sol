// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ExchangeCalendar} from "../src/ExchangeCalendar.sol";
import {IExchangeCalendar} from "../src/interfaces/IExchangeCalendar.sol";
import {MockDayFlags} from "./mocks/MockDayFlags.sol";
import {Test} from "forge-std/Test.sol";

contract ExchangeCalendarTest is Test {
    uint32 constant FRI = 20777; // 2026-11-20
    uint32 constant MON = 20780; // 2026-11-23
    uint32 constant WED = 20782; // 2026-11-25
    uint32 constant THANKSGIVING = 20783; // 2026-11-26
    uint32 constant BLACK_FRIDAY = 20784; // 2026-11-27, early close

    address timelock = makeAddr("timelock");
    MockDayFlags flags;
    ExchangeCalendar cal;

    function setUp() public {
        flags = new MockDayFlags();
        cal = new ExchangeCalendar(timelock, address(flags));
    }

    function _one(uint32 d, uint64 o, uint64 c)
        internal
        pure
        returns (uint32[] memory ds, IExchangeCalendar.Session[] memory ss)
    {
        ds = new uint32[](1);
        ss = new IExchangeCalendar.Session[](1);
        ds[0] = d;
        ss[0] = IExchangeCalendar.Session(o, c);
    }

    function _set(uint32 d, uint64 o, uint64 c) internal {
        (uint32[] memory ds, IExchangeCalendar.Session[] memory ss) = _one(d, o, c);
        vm.prank(timelock);
        cal.setSessions(ds, ss);
    }

    function _loadVectors() internal {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/test/vectors/calendar.json"));
        uint256[] memory d = vm.parseJsonUintArray(json, ".dayIds");
        uint256[] memory o = vm.parseJsonUintArray(json, ".openTs");
        uint256[] memory c = vm.parseJsonUintArray(json, ".closeTs");
        uint32[] memory ds = new uint32[](d.length);
        IExchangeCalendar.Session[] memory ss = new IExchangeCalendar.Session[](d.length);
        for (uint256 i; i < d.length; ++i) {
            ds[i] = uint32(d[i]);
            ss[i] = IExchangeCalendar.Session(uint64(o[i]), uint64(c[i]));
        }
        vm.prank(timelock);
        cal.setSessions(ds, ss);
    }

    function test_vectors_allAcceptedAndShaped() public {
        _loadVectors();
        assertEq(cal.session(MON).openTs, 1_795_444_200);
        assertEq(cal.session(MON).closeTs, 1_795_467_600);
        assertEq(cal.session(BLACK_FRIDAY).closeTs - cal.session(BLACK_FRIDAY).openTs, 12_600);
        assertEq(cal.session(20811).closeTs - cal.session(20811).openTs, 12_600); // 2026-12-24
        assertFalse(cal.isTradingDay(THANKSGIVING));
        assertFalse(cal.isTradingDay(20778)); // Saturday
        assertTrue(cal.isTradingDay(20759)); // 2026-11-02, first EST Monday
        assertEq(cal.session(20759).openTs, 1_793_629_800);
        assertEq(cal.session(20892).openTs, 1_805_117_400); // 2027-03-15, first EDT Monday
    }

    function test_prevTradingDay_acrossWeekendAndHoliday() public {
        _loadVectors();
        assertEq(cal.prevTradingDay(MON, 10), FRI);
        assertEq(cal.prevTradingDay(BLACK_FRIDAY, 10), WED);
        assertEq(cal.prevTradingDay(MON, 2), 0); // Sat, Sun only
        assertEq(cal.prevTradingDay(3, 10), 0); // no underflow below day 0
    }

    function test_setSessions_onlyTimelock() public {
        (uint32[] memory ds, IExchangeCalendar.Session[] memory ss) = _one(MON, 1_795_444_200, 1_795_467_600);
        vm.expectRevert(IExchangeCalendar.NotTimelock.selector);
        cal.setSessions(ds, ss);
    }

    function test_setSessions_lengthMismatch() public {
        uint32[] memory ds = new uint32[](2);
        IExchangeCalendar.Session[] memory ss = new IExchangeCalendar.Session[](1);
        vm.prank(timelock);
        vm.expectRevert(IExchangeCalendar.LengthMismatch.selector);
        cal.setSessions(ds, ss);
    }

    function test_setSessions_rejectsMalformed() public {
        uint64 start = uint64(MON) * 86_400;
        uint64[2][5] memory bad = [
            [start + 52_200, start + 52_200 + 23_399], // wrong length
            [start - 1, start - 1 + 23_400], // opens before the UTC day
            [start + 70_000, start + 70_000 + 23_400], // closes after the UTC day
            [start + 60_000, start + 50_000], // open after close
            [start + 52_200, 0] // closed but open set
        ];
        for (uint256 i; i < bad.length; ++i) {
            (uint32[] memory ds, IExchangeCalendar.Session[] memory ss) = _one(MON, bad[i][0], bad[i][1]);
            vm.prank(timelock);
            vm.expectRevert(abi.encodeWithSelector(IExchangeCalendar.BadSession.selector, MON));
            cal.setSessions(ds, ss);
        }
    }

    function test_setSessions_clearAndEmit() public {
        _set(MON, 1_795_444_200, 1_795_467_600);
        vm.expectEmit(true, false, false, true);
        emit IExchangeCalendar.SessionSet(MON, 0, 0);
        _set(MON, 0, 0);
        assertFalse(cal.isTradingDay(MON));
    }

    function test_setSessions_lockedOnceMarketsExist() public {
        flags.set(MON, true);
        (uint32[] memory ds, IExchangeCalendar.Session[] memory ss) = _one(MON, 1_795_444_200, 1_795_467_600);
        vm.prank(timelock);
        vm.expectRevert(abi.encodeWithSelector(IExchangeCalendar.DayLocked.selector, MON));
        cal.setSessions(ds, ss);
    }

    function testFuzz_sessionValidity(uint32 dayId, uint64 openOffset, bool early) public {
        dayId = uint32(bound(dayId, 1, 100_000));
        openOffset = uint64(bound(openOffset, 0, 86_399));
        uint64 len = early ? 12_600 : 23_400;
        uint64 start = uint64(dayId) * 86_400;
        uint64 o = start + openOffset;
        (uint32[] memory ds, IExchangeCalendar.Session[] memory ss) = _one(dayId, o, o + len);
        vm.prank(timelock);
        if (o + len >= start + 86_400) {
            vm.expectRevert(abi.encodeWithSelector(IExchangeCalendar.BadSession.selector, dayId));
            cal.setSessions(ds, ss);
        } else {
            cal.setSessions(ds, ss);
            assertEq(cal.session(dayId).closeTs, o + len);
        }
    }
}
