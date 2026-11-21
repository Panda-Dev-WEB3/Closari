// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ILMSRMarket} from "../src/interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "../src/interfaces/IMarketFactory.sol";
import {MockMarket} from "./mocks/MockMarket.sol";
import {Fixture} from "./utils/Fixture.sol";

contract MarketFactoryFeesTest is Fixture {
    function test_fees_launchDefaults() public view {
        (uint16 base, uint16 ramp) = factory.fees();
        assertEq(base, 50);
        assertEq(ramp, 250);
    }

    function test_setFees_onlyTimelock() public {
        vm.expectRevert(IMarketFactory.NotTimelock.selector);
        factory.setFees(25, 250);
        vm.prank(guardian);
        vm.expectRevert(IMarketFactory.NotTimelock.selector);
        factory.setFees(25, 250);
    }

    function test_setFees_capsAndEvent() public {
        vm.startPrank(timelock);
        vm.expectRevert(IMarketFactory.BadFees.selector);
        factory.setFees(201, 250);
        vm.expectRevert(IMarketFactory.BadFees.selector);
        factory.setFees(50, 501);
        vm.expectEmit(address(factory));
        emit IMarketFactory.FeesSet(200, 500);
        factory.setFees(200, 500);
        vm.stopPrank();
        (uint16 base, uint16 ramp) = factory.fees();
        assertEq(base, 200);
        assertEq(ramp, 500);
    }

    function test_listing_snapshotsFeesAndPrior() public {
        vm.prank(timelock);
        factory.setFees(25, 250);
        address[] memory m = _listFri();
        vm.prank(timelock);
        factory.setFees(200, 500); // later edits never reach a listed market (I9)
        for (uint256 i; i < m.length; ++i) {
            if (m[i] == address(0)) continue;
            ILMSRMarket.Config memory c = MockMarket(m[i]).config();
            assertEq(c.baseFeeBps, 25);
            assertEq(c.rampMaxBps, 250);
            assertEq(c.priorWad.length, c.n);
            uint256 sum;
            for (uint256 j; j < c.n; ++j) {
                sum += c.priorWad[j];
            }
            assertEq(sum, 1e18);
        }
    }
}
