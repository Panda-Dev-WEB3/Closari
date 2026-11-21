// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {MarketFactory} from "../src/MarketFactory.sol";
import {IMarketFactory} from "../src/interfaces/IMarketFactory.sol";
import {MockMarket} from "./mocks/MockMarket.sol";
import {Fixture} from "./utils/Fixture.sol";

contract MarketFactoryAdminTest is Fixture {
    function test_constructor_launchTemplateAndBounty() public view {
        (int16[] memory s, int16[] memory e, bool u) = factory.template();
        assertEq(s.length, 6);
        assertEq(s[0], -500);
        assertEq(s[5], 500);
        assertEq(e.length, 4);
        assertEq(e[1], -50);
        assertTrue(u);
        assertEq(factory.listingBounty(), 1e6);
        assertEq(factory.timelock(), timelock);
        assertEq(factory.guardian(), guardian);
    }

    function test_constructor_rejectsZeroAddress() public {
        MarketFactory.Params memory p = MarketFactory.Params({
            calendar: address(calendar),
            allowList: address(allowList),
            pool: address(pool),
            oracle: address(oracle),
            router: address(router),
            staking: staking,
            pyth: address(pyth),
            marketImpl: address(0),
            timelock: timelock,
            guardian: guardian
        });
        vm.expectRevert(MarketFactory.ZeroAddress.selector);
        new MarketFactory(p);
    }

    function test_setTemplate_onlyTimelock() public {
        vm.expectRevert(IMarketFactory.NotTimelock.selector);
        factory.setTemplate(new int16[](1), new int16[](0), false);
    }

    function test_setTemplate_validation() public {
        int16[] memory nine = new int16[](9);
        for (uint256 i; i < 9; ++i) {
            nine[i] = int16(int256(i) * 10 - 40);
        }
        int16[] memory eight = new int16[](8);
        for (uint256 i; i < 8; ++i) {
            eight[i] = int16(int256(i) * 10 - 40);
        }
        int16[] memory notIncreasing = new int16[](2);
        (notIncreasing[0], notIncreasing[1]) = (100, 100);
        int16[] memory tooLow = new int16[](1);
        tooLow[0] = -10_000;
        int16[] memory tooHigh = new int16[](1);
        tooHigh[0] = 10_000;
        int16[] memory none = new int16[](0);

        vm.startPrank(timelock);
        vm.expectRevert(IMarketFactory.BadTemplate.selector);
        factory.setTemplate(nine, none, true);
        vm.expectRevert(IMarketFactory.BadTemplate.selector);
        factory.setTemplate(none, eight, true);
        vm.expectRevert(IMarketFactory.BadTemplate.selector);
        factory.setTemplate(notIncreasing, none, true);
        vm.expectRevert(IMarketFactory.BadTemplate.selector);
        factory.setTemplate(none, notIncreasing, true);
        vm.expectRevert(IMarketFactory.BadTemplate.selector);
        factory.setTemplate(tooLow, none, true);
        vm.expectRevert(IMarketFactory.BadTemplate.selector);
        factory.setTemplate(tooHigh, none, true);
        vm.expectRevert(IMarketFactory.BadTemplate.selector);
        factory.setTemplate(none, none, false);
        vm.stopPrank();
    }

    function test_setTemplate_appliesToNextListing() public {
        int16[] memory one = new int16[](1);
        one[0] = 100;
        vm.expectEmit(false, false, false, true);
        emit IMarketFactory.TemplateSet(one, new int16[](0), false);
        vm.prank(timelock);
        factory.setTemplate(one, new int16[](0), false);
        address[] memory m = _listFri();
        assertEq(m.length, 1);
        assertEq(MockMarket(m[0]).config().edges[0], 19_000_000_000);
    }

    function test_listingBounty_capAndZero() public {
        vm.expectRevert(IMarketFactory.NotTimelock.selector);
        factory.setListingBounty(0);
        vm.prank(timelock);
        vm.expectRevert(IMarketFactory.BountyTooHigh.selector);
        factory.setListingBounty(5e6 + 1);
        vm.prank(timelock);
        factory.setListingBounty(0);
        _listFri();
        assertEq(router.creditCalls(), 0);
    }

    function test_guardianSwitches() public {
        vm.expectRevert(IMarketFactory.NotGuardian.selector);
        factory.setListingPaused(true);
        vm.prank(guardian);
        factory.setListingPaused(true);
        assertTrue(factory.listingPaused());

        address[] memory t = new address[](1);
        uint32[] memory d = new uint32[](2);
        vm.expectRevert(IMarketFactory.NotGuardian.selector);
        factory.setSkip(t, new uint32[](1), true);
        vm.prank(guardian);
        vm.expectRevert(IMarketFactory.LengthMismatch.selector);
        factory.setSkip(t, d, true);
    }

    function test_predictMarket_distinctPerIndexDayAndToken() public view {
        address a = factory.predictMarket(address(nvda), FRI, 0);
        assertTrue(a != factory.predictMarket(address(nvda), FRI, 1));
        assertTrue(a != factory.predictMarket(address(nvda), MON, 0));
        assertTrue(a != factory.predictMarket(address(feed), FRI, 0));
        assertEq(a, factory.predictMarket(address(nvda), FRI, 0));
    }

    function test_guardianVoid() public {
        address[] memory m = _listFri();
        vm.expectRevert(IMarketFactory.NotGuardian.selector);
        factory.guardianVoid(m[0], keccak256("closure"));

        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.UnknownMarket.selector, address(0xBEEF)));
        factory.guardianVoid(address(0xBEEF), keccak256("closure"));

        vm.expectEmit(true, false, false, true);
        emit IMarketFactory.GuardianVoided(m[0], keccak256("closure"));
        vm.prank(guardian);
        factory.guardianVoid(m[0], keccak256("closure"));
        assertEq(MockMarket(m[0]).lastVoidReason(), 9); // VoidReason.GUARDIAN

        vm.warp(FRI_CLOSE - 600);
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.PastHalt.selector, m[1]));
        factory.guardianVoid(m[1], keccak256("closure"));
    }
}
