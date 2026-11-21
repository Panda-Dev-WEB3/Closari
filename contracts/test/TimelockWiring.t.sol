// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ExchangeCalendar} from "../src/ExchangeCalendar.sol";
import {IExchangeCalendar} from "../src/interfaces/IExchangeCalendar.sol";
import {MockDayFlags} from "./mocks/MockDayFlags.sol";
import {Test} from "forge-std/Test.sol";
import {ERC7821} from "solady/accounts/ERC7821.sol";
import {Timelock} from "solady/accounts/Timelock.sol";

contract TimelockWiringTest is Test {
    bytes32 constant MODE = 0x0100000000007821000100000000000000000000000000000000000000000000;
    uint32 constant MON = 20780;

    function test_calendarEditWaits48Hours_andDeployerHoldsNoRole() public {
        address multisig = makeAddr("multisig");
        address[] memory roles = new address[](1);
        roles[0] = multisig;
        Timelock tl = new Timelock();
        tl.initialize(48 hours, address(0), roles, roles, roles);
        ExchangeCalendar cal = new ExchangeCalendar(address(tl), address(new MockDayFlags()));

        uint32[] memory d = new uint32[](1);
        IExchangeCalendar.Session[] memory s = new IExchangeCalendar.Session[](1);
        (d[0], s[0]) = (MON, IExchangeCalendar.Session(1_795_444_200, 1_795_467_600));
        ERC7821.Call[] memory calls = new ERC7821.Call[](1);
        calls[0] =
            ERC7821.Call({to: address(cal), value: 0, data: abi.encodeCall(ExchangeCalendar.setSessions, (d, s))});
        bytes memory data = abi.encode(calls, abi.encode(bytes32(0), bytes32("calendar-2026Q4")));

        vm.prank(multisig);
        vm.expectRevert(IExchangeCalendar.NotTimelock.selector);
        cal.setSessions(d, s);

        vm.prank(multisig);
        tl.propose(MODE, data, 48 hours);
        vm.prank(multisig);
        vm.expectRevert();
        tl.execute(MODE, data); // not ready yet
        vm.warp(block.timestamp + 48 hours);
        vm.prank(multisig);
        tl.execute(MODE, data);
        assertTrue(cal.isTradingDay(MON));

        for (uint256 role; role <= 3; ++role) {
            assertFalse(tl.hasRole(address(this), role));
        }
        assertEq(tl.minDelay(), 48 hours);
    }
}
