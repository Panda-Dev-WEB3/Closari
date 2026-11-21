// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {StockTokenAllowList} from "../src/StockTokenAllowList.sol";
import {IStockTokenAllowList} from "../src/interfaces/IStockTokenAllowList.sol";
import {MockAggregator} from "./mocks/MockAggregator.sol";
import {
    MockBeacon,
    MockBeaconBurnsGas,
    MockBeaconCostly,
    MockBeaconDirtyReturn,
    MockBeaconShortReturn
} from "./mocks/MockBeacon.sol";
import {MockStockToken, MockStockTokenLookalike} from "./mocks/MockStockToken.sol";
import {Test} from "forge-std/Test.sol";

contract StockTokenAllowListTest is Test {
    address timelock = makeAddr("timelock");
    MockBeacon beacon;
    MockStockToken nvda;
    MockStockToken spy;
    MockStockTokenLookalike fake;
    MockAggregator feed8;
    MockAggregator feed18;
    StockTokenAllowList list;

    function setUp() public {
        beacon = new MockBeacon(makeAddr("implementation"));
        nvda = new MockStockToken(1e18);
        spy = new MockStockToken(1.001718e18);
        fake = new MockStockTokenLookalike(1e18);
        feed8 = new MockAggregator(8, "RHNVDA / USD");
        feed18 = new MockAggregator(18, "BAD / USD");
        list = new StockTokenAllowList(address(beacon), address(nvda).codehash, timelock);
    }

    function _asset(address feed) internal pure returns (IStockTokenAllowList.Asset memory) {
        return IStockTokenAllowList.Asset({
            pythId: keccak256("test:NVDA"),
            clFeed: feed,
            tickPrice8: 50_000_000,
            budgetAbove: 2_000e6,
            budgetRange: 2_000e6,
            budgetUpDown: 2_000e6,
            volBps: 300,
            listed: true
        });
    }

    function test_isGenuine_matchesCodehashAndLiveBeacon() public {
        assertTrue(list.isGenuine(address(nvda)));
        assertTrue(list.isGenuine(address(spy)));
        assertFalse(list.isGenuine(address(fake)));
        assertFalse(list.isGenuine(makeAddr("eoa")));
        beacon.setImplementation(address(0));
        assertFalse(list.isGenuine(address(nvda)));
        beacon.setImplementation(makeAddr("implementation2"));
        assertTrue(list.isGenuine(address(nvda)));
        beacon.setReverts(true);
        assertFalse(list.isGenuine(address(nvda)));
    }

    function test_isGenuine_failsClosedOnShortReturn() public {
        StockTokenAllowList l =
            new StockTokenAllowList(address(new MockBeaconShortReturn()), address(nvda).codehash, timelock);
        assertFalse(l.isGenuine(address(nvda)));
    }

    function test_isGenuine_failsClosedOnDirtyAddressWord() public {
        StockTokenAllowList l =
            new StockTokenAllowList(address(new MockBeaconDirtyReturn()), address(nvda).codehash, timelock);
        assertFalse(l.isGenuine(address(nvda)));
    }

    function test_isGenuine_failsClosedOnCodelessBeacon() public {
        StockTokenAllowList l = new StockTokenAllowList(makeAddr("codelessBeacon"), address(nvda).codehash, timelock);
        assertFalse(l.isGenuine(address(nvda)));
    }

    function test_isGenuine_failsClosedOnGasBurningBeacon() public {
        StockTokenAllowList l =
            new StockTokenAllowList(address(new MockBeaconBurnsGas()), address(nvda).codehash, timelock);
        assertFalse(l.isGenuine(address(nvda)));
    }

    function test_isGenuine_toleratesCostlierBeacon() public {
        address impl = makeAddr("implementation");
        StockTokenAllowList l =
            new StockTokenAllowList(address(new MockBeaconCostly(impl)), address(nvda).codehash, timelock);
        assertTrue(l.isGenuine(address(nvda)));
    }

    function test_setAsset_onlyTimelock() public {
        vm.expectRevert(IStockTokenAllowList.NotTimelock.selector);
        list.setAsset(address(nvda), _asset(address(feed8)));
    }

    function test_setAsset_rejectsLookalike() public {
        vm.prank(timelock);
        vm.expectRevert(abi.encodeWithSelector(IStockTokenAllowList.NotGenuine.selector, address(fake)));
        list.setAsset(address(fake), _asset(address(feed8)));
    }

    function test_setAsset_rejectsBadFields() public {
        IStockTokenAllowList.Asset memory a = _asset(address(feed8));
        a.pythId = bytes32(0);
        vm.prank(timelock);
        vm.expectRevert(IStockTokenAllowList.BadAsset.selector);
        list.setAsset(address(nvda), a);

        a = _asset(address(feed8));
        a.tickPrice8 = 0;
        vm.prank(timelock);
        vm.expectRevert(IStockTokenAllowList.BadAsset.selector);
        list.setAsset(address(nvda), a);

        vm.prank(timelock);
        vm.expectRevert(abi.encodeWithSelector(IStockTokenAllowList.BadFeedDecimals.selector, uint8(18)));
        list.setAsset(address(nvda), _asset(address(feed18)));
    }

    function test_setAsset_volBpsBounds() public {
        IStockTokenAllowList.Asset memory a = _asset(address(feed8));
        a.volBps = 24;
        vm.prank(timelock);
        vm.expectRevert(IStockTokenAllowList.BadAsset.selector);
        list.setAsset(address(nvda), a);
        a.volBps = 2_001;
        vm.prank(timelock);
        vm.expectRevert(IStockTokenAllowList.BadAsset.selector);
        list.setAsset(address(nvda), a);
        a.listed = false; // an unlisted asset may carry volBps 0
        a.volBps = 0;
        vm.prank(timelock);
        list.setAsset(address(nvda), a);
        a.listed = true;
        a.volBps = 2_000;
        vm.prank(timelock);
        list.setAsset(address(nvda), a);
        assertEq(list.asset(address(nvda)).volBps, 2_000);
    }

    function test_setAsset_rejectsCodelessFeed() public {
        vm.prank(timelock);
        vm.expectRevert(IStockTokenAllowList.BadAsset.selector);
        list.setAsset(address(nvda), _asset(address(0)));

        vm.prank(timelock);
        vm.expectRevert(IStockTokenAllowList.BadAsset.selector);
        list.setAsset(address(nvda), _asset(makeAddr("eoaFeed")));
    }

    function test_setAsset_storesAndEmits() public {
        IStockTokenAllowList.Asset memory a = _asset(address(feed8));
        vm.expectEmit(true, false, false, true);
        emit IStockTokenAllowList.AssetSet(address(nvda), a);
        vm.prank(timelock);
        list.setAsset(address(nvda), a);
        IStockTokenAllowList.Asset memory got = list.asset(address(nvda));
        assertEq(got.pythId, a.pythId);
        assertEq(got.clFeed, address(feed8));
        assertEq(got.tickPrice8, 50_000_000);
        assertEq(got.budgetRange, 2_000e6);
        assertTrue(got.listed);
        assertEq(list.asset(address(spy)).pythId, bytes32(0));
    }
}
