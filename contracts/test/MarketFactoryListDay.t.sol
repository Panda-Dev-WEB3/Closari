// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {MarketFactory} from "../src/MarketFactory.sol";
import {IExchangeCalendar} from "../src/interfaces/IExchangeCalendar.sol";
import {ILMSRMarket} from "../src/interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "../src/interfaces/IMarketFactory.sol";
import {ISettlementOracle} from "../src/interfaces/ISettlementOracle.sol";
import {PriorMath} from "../src/lib/PriorMath.sol";
import {StrikeMath} from "../src/lib/StrikeMath.sol";
import {MockMarket} from "./mocks/MockMarket.sol";
import {MockPythWrongId} from "./mocks/MockPythWrongId.sol";
import {Fixture} from "./utils/Fixture.sol";
import {PythErrors} from "@pythnetwork/pyth-sdk-solidity/PythErrors.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

contract MarketFactoryListDayTest is Fixture {
    bytes[] internal empty;

    // ---------- success ----------

    function test_firstListing_createsEightConfiguredMarkets() public {
        vm.warp(FRI_OPEN - 3 hours);
        address[] memory expected = new address[](8);
        for (uint256 i; i < 8; ++i) {
            expected[i] = factory.predictMarket(address(nvda), FRI, i);
        }
        bytes[] memory u = _pythUpdate(NVDA_PRICE, 9_000_000, -8, uint64(block.timestamp));
        vm.expectEmit(true, true, false, true);
        emit IMarketFactory.DayListed(address(nvda), FRI, NVDA_PRICE, 1e18, expected);
        vm.prank(lister);
        address[] memory m = factory.listDay{value: 1 ether}(address(nvda), FRI, u);

        assertEq(m.length, 8);
        for (uint256 i; i < 8; ++i) {
            assertEq(m[i], expected[i]);
            assertTrue(factory.isMarket(m[i]));
            assertEq(pool.allocated(m[i]), BUDGET);
            assertTrue(MockMarket(m[i]).initialized());
            assertEq(MockMarket(m[i]).pool(), address(pool));
            assertEq(MockMarket(m[i]).staking(), staking);
        }
        assertEq(lister.balance, 1 ether - 1); // only Pyth's 1-wei fee kept
        assertEq(router.bounties(lister), 1e6);
        assertTrue(factory.hasMarkets(FRI));

        ILMSRMarket.Config memory above = MockMarket(m[3]).config();
        assertEq(uint8(above.kind), uint8(IMarketFactory.Kind.ABOVE));
        assertEq(above.n, 2);
        assertEq(above.edges.length, 1);
        assertEq(above.edges[0], 19_000_000_000); // +1% of $188.12 → $190.00
        assertEq(above.openTs, FRI_OPEN);
        assertEq(above.closeTs, FRI_CLOSE);
        assertEq(above.haltTs, FRI_CLOSE - 600);
        assertEq(above.createdTs, block.timestamp);
        assertEq(above.multiplierSnapshot, 1e18);
        assertEq(above.budget, BUDGET);
        assertEq(above.bWad, PriorMath.liquidity(above.budget, above.priorWad) * 1e12);

        ILMSRMarket.Config memory range = MockMarket(m[6]).config();
        assertEq(uint8(range.kind), uint8(IMarketFactory.Kind.RANGE));
        assertEq(range.n, 5);
        assertEq(range.edges[0], 18_450_000_000);
        assertEq(range.edges[1], 18_700_000_000);
        assertEq(range.edges[2], 18_900_000_000);
        assertEq(range.edges[3], 19_200_000_000);
        assertEq(range.bWad, PriorMath.liquidity(range.budget, range.priorWad) * 1e12);

        ILMSRMarket.Config memory updown = MockMarket(m[7]).config();
        assertEq(uint8(updown.kind), uint8(IMarketFactory.Kind.UPDOWN));
        assertEq(updown.edges.length, 0);

        IMarketFactory.DayInfo memory info = factory.dayInfo(address(nvda), FRI);
        assertEq(info.pythId, PYTH_ID);
        assertEq(info.clFeed, address(feed));
        assertEq(info.refPrice8, NVDA_PRICE);
        assertEq(info.markets.length, 8);
        assertEq(factory.marketsOf(address(nvda), FRI)[7], m[7]);
    }

    function test_budgetBound_worstCaseLossWithinBudget() public {
        address[] memory m = _listFri();
        for (uint256 i; i < m.length; ++i) {
            if (m[i] == address(0)) continue;
            ILMSRMarket.Config memory c = MockMarket(m[i]).config();
            uint256 pMin = type(uint256).max;
            for (uint256 j; j < c.n; ++j) {
                if (c.priorWad[j] < pMin) pMin = c.priorWad[j];
            }
            uint256 lnInv = uint256(FixedPointMathLib.lnWad(int256(1e36 / pMin)));
            assertLe((c.bWad / 1e12) * lnInv / 1e18, c.budget);
        }
    }

    function test_pythReference_appliesMultiplierOnce() public {
        nvda.setMultiplier(1_000_775_159_164_630_595);
        _listFri();
        assertEq(factory.dayInfo(address(nvda), FRI).refPrice8, 18_826_582_294);
        assertEq(factory.dayInfo(address(nvda), FRI).multiplierSnapshot, 1_000_775_159_164_630_595);
    }

    function test_previousFinalClose_isRescaledByCurrentMultiplier() public {
        _listFri();
        _finalClose(FRI, NVDA_PRICE, ISettlementOracle.VoidReason.NONE);
        nvda.setMultiplier(1.01e18); // dividend step after Friday's close
        vm.warp(MON_OPEN - 3 hours);
        vm.prank(lister);
        factory.listDay(address(nvda), MON, empty);
        assertEq(factory.dayInfo(address(nvda), MON).refPrice8, 19_000_120_000);
        assertEq(factory.dayInfo(address(nvda), MON).multiplierSnapshot, 1.01e18);
    }

    function test_walksPastVoidedDayToEarlierFinal() public {
        vm.warp(THU_OPEN - 3 hours);
        _listWithPyth(THU, 18_000_000_000);
        _finalClose(THU, 18_000_000_000, ISettlementOracle.VoidReason.NONE);
        vm.warp(FRI_OPEN - 3 hours);
        vm.prank(lister);
        factory.listDay(address(nvda), FRI, empty); // reference from Thursday
        assertEq(factory.dayInfo(address(nvda), FRI).refPrice8, 18_000_000_000);
        _finalClose(FRI, 0, ISettlementOracle.VoidReason.NO_PRICE);
        vm.warp(MON_OPEN - 3 hours);
        vm.prank(lister);
        factory.listDay(address(nvda), MON, empty); // Friday voided → Thursday again
        assertEq(factory.dayInfo(address(nvda), MON).refPrice8, 18_000_000_000);
    }

    function test_voidedPreviousDay_withoutEarlierFinal_needsPyth() public {
        _listFri();
        _finalClose(FRI, NVDA_PRICE, ISettlementOracle.VoidReason.CONF_WIDE);
        vm.warp(MON_OPEN - 3 hours);
        vm.prank(lister);
        vm.expectRevert(IMarketFactory.ReferenceUpdateRequired.selector);
        factory.listDay(address(nvda), MON, empty);
        _listWithPyth(MON, 19_100_000_000);
        assertEq(factory.dayInfo(address(nvda), MON).refPrice8, 19_100_000_000);
    }

    function test_listingBoundary_lastAllowedSecond() public {
        vm.warp(FRI_CLOSE - 4201);
        _listWithPyth(FRI, NVDA_PRICE);
        assertTrue(factory.hasMarkets(FRI));
    }

    function test_caScheduledAfterWindow_isAllowed() public {
        nvda.schedule(1.01e18, FRI_CLOSE + 3601);
        _listFri();
        assertTrue(factory.hasMarkets(FRI));
    }

    // ---------- partial listings ----------

    function test_poolRefusal_skipsOnlyThatMarket() public {
        address skipped = factory.predictMarket(address(nvda), FRI, 2);
        pool.setRefuseMarket(skipped, true);
        vm.warp(FRI_OPEN - 3 hours);
        bytes[] memory u = _updateNow(NVDA_PRICE);
        vm.expectEmit(true, true, false, true);
        emit IMarketFactory.MarketSkipped(address(nvda), FRI, 2, 3);
        address[] memory m = _listWith(FRI, u);
        assertEq(m[2], address(0));
        assertFalse(factory.isMarket(skipped));
        assertEq(skipped.code.length, 0);
        for (uint256 i; i < 8; ++i) {
            if (i != 2) assertTrue(m[i] != address(0));
        }
    }

    function test_poolOutOfGas_revertsInsteadOfSkipping() public {
        pool.setBurnGas(true);
        vm.warp(FRI_OPEN - 3 hours);
        bytes[] memory u = _pythUpdate(NVDA_PRICE, 9_000_000, -8, uint64(block.timestamp));
        vm.prank(lister);
        vm.expectRevert(IMarketFactory.AllocationFailed.selector);
        factory.listDay{value: 1, gas: 3_000_000}(address(nvda), FRI, u);
    }

    function test_budgetOutOfRange_revertsNoMarketsOpened() public {
        _setNvda(PYTH_ID, true, 1e6); // 1 USDG → b ≈ 1.44 shares < 1,000
        vm.warp(FRI_OPEN - 3 hours);
        bytes[] memory u = _updateNow(NVDA_PRICE);
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.NoMarketsOpened.selector, address(nvda), FRI));
        _listWith(FRI, u);
        assertFalse(factory.hasMarkets(FRI));
        assertEq(factory.dayInfo(address(nvda), FRI).createdTs, 0);
        assertEq(pool.allocateCalls(), 0);
        assertEq(router.creditCalls(), 0);
    }

    function test_allPoolRefusals_revertNoMarketsOpened() public {
        pool.setRefuseAll(true);
        vm.warp(FRI_OPEN - 3 hours);
        bytes[] memory u = _updateNow(NVDA_PRICE);
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.NoMarketsOpened.selector, address(nvda), FRI));
        _listWith(FRI, u);
        assertEq(router.creditCalls(), 0);
        assertFalse(factory.hasMarkets(FRI));

        pool.setRefuseAll(false);
        address[] memory m = _listWith(FRI, u); // the day stays listable
        assertEq(m.length, 8);
        assertTrue(factory.hasMarkets(FRI));
        assertEq(router.creditCalls(), 1);
    }

    function test_upDown_skippedAtOpen() public {
        vm.warp(FRI_OPEN);
        bytes[] memory u = _updateNow(NVDA_PRICE);
        vm.expectEmit(true, true, false, true);
        emit IMarketFactory.MarketSkipped(address(nvda), FRI, 7, 5);
        address[] memory m = _listWith(FRI, u);
        assertEq(m[7], address(0));
        assertFalse(factory.isMarket(factory.predictMarket(address(nvda), FRI, 7)));
        for (uint256 i; i < 7; ++i) {
            assertTrue(m[i] != address(0));
        }
    }

    function test_upDown_listedOneSecondBeforeOpen() public {
        vm.warp(FRI_OPEN - 1);
        address[] memory m = _listWithPyth(FRI, NVDA_PRICE);
        assertTrue(m[7] != address(0));
        assertEq(uint8(MockMarket(m[7]).config().kind), uint8(IMarketFactory.Kind.UPDOWN));
    }

    function test_collapsedStrikes_andSingleEdgeRange() public {
        vm.warp(FRI_OPEN - 3 hours);
        address[] memory m = _listWithPyth(FRI, 100_000_000); // $1.00 at a $0.50 tick
        assertTrue(m[0] != address(0));
        for (uint256 i = 1; i < 6; ++i) {
            assertEq(m[i], address(0));
        }
        ILMSRMarket.Config memory range = MockMarket(m[6]).config();
        assertEq(range.n, 2);
        assertEq(range.edges[0], 100_000_000);
    }

    function test_noEdges_skipsRangeKeepsUpDown() public {
        vm.warp(FRI_OPEN - 3 hours);
        bytes[] memory u = _updateNow(10_000_000); // $0.10: every strike rounds to 0
        vm.expectEmit(true, true, false, true);
        emit IMarketFactory.MarketSkipped(address(nvda), FRI, 6, 4);
        address[] memory m = _listWith(FRI, u);
        assertEq(m[6], address(0));
        assertTrue(m[7] != address(0));
    }

    // ---------- refusals ----------

    function test_refusals_stateAndAsset() public {
        vm.warp(FRI_OPEN - 3 hours);
        bytes[] memory u = _pythUpdate(NVDA_PRICE, 9_000_000, -8, uint64(block.timestamp));

        vm.prank(guardian);
        factory.setListingPaused(true);
        vm.expectRevert(IMarketFactory.ListingIsPaused.selector);
        factory.listDay{value: 1}(address(nvda), FRI, u);
        vm.prank(guardian);
        factory.setListingPaused(false);

        address[] memory t = new address[](1);
        uint32[] memory d = new uint32[](1);
        (t[0], d[0]) = (address(nvda), FRI);
        vm.prank(guardian);
        factory.setSkip(t, d, true);
        assertTrue(factory.isSkipped(address(nvda), FRI));
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.DaySkipped.selector, address(nvda), FRI));
        factory.listDay{value: 1}(address(nvda), FRI, u);
        vm.prank(guardian);
        factory.setSkip(t, d, false);

        _setNvda(PYTH_ID, false, BUDGET);
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.AssetNotListed.selector, address(nvda)));
        factory.listDay{value: 1}(address(nvda), FRI, u);
        _setNvda(PYTH_ID, true, BUDGET);

        beacon.setImplementation(address(0));
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.AssetNotListed.selector, address(nvda)));
        factory.listDay{value: 1}(address(nvda), FRI, u);
        beacon.setImplementation(makeAddr("implementation"));

        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.NoSession.selector, SAT));
        factory.listDay{value: 1}(address(nvda), SAT, u);

        factory.listDay{value: 1}(address(nvda), FRI, u);
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.AlreadyListed.selector, address(nvda), FRI));
        factory.listDay{value: 1}(address(nvda), FRI, u);
    }

    function test_refusals_timingCorporateActionsQueue() public {
        vm.warp(FRI_CLOSE - 4200);
        bytes[] memory u = _pythUpdate(NVDA_PRICE, 9_000_000, -8, uint64(block.timestamp));
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.TooLate.selector, FRI));
        factory.listDay{value: 1}(address(nvda), FRI, u);

        vm.warp(FRI_OPEN - 3 hours);
        u = _pythUpdate(NVDA_PRICE, 9_000_000, -8, uint64(block.timestamp));
        nvda.setOraclePaused(true);
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.OraclePaused.selector, address(nvda)));
        factory.listDay{value: 1}(address(nvda), FRI, u);
        nvda.setOraclePaused(false);

        nvda.schedule(1.01e18, FRI_CLOSE + 3600);
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.CorporateActionPending.selector, address(nvda)));
        factory.listDay{value: 1}(address(nvda), FRI, u);
        nvda.schedule(1e18, 0);

        pool.setMaturedQueuePending(true);
        vm.expectRevert(IMarketFactory.QueuePending.selector);
        factory.listDay{value: 1}(address(nvda), FRI, u);
    }

    function test_refusal_tooEarly_beforePreviousClose() public {
        _listFri();
        _finalClose(FRI, NVDA_PRICE, ISettlementOracle.VoidReason.NONE);
        vm.warp(FRI_CLOSE - 1);
        vm.prank(lister);
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.TooEarly.selector, MON));
        factory.listDay(address(nvda), MON, empty);
        vm.warp(FRI_CLOSE);
        vm.prank(lister);
        factory.listDay(address(nvda), MON, empty);
        assertTrue(factory.hasMarkets(MON));
    }

    function test_refusal_tooEarly_farFuture() public {
        vm.warp(THU_OPEN - 3 hours);
        bytes[] memory u = _updateNow(NVDA_PRICE);
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.TooEarly.selector, TUE));
        factory.listDay{value: 1}(address(nvda), TUE, u);
    }

    function test_refusal_previousDayNotFinal() public {
        _listFri();
        vm.warp(MON_OPEN - 3 hours);
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.PreviousDayNotFinal.selector, address(nvda), FRI));
        factory.listDay(address(nvda), MON, empty);
    }

    function test_refusals_pythReference() public {
        vm.warp(FRI_OPEN - 3 hours);
        uint64 nowTs = uint64(block.timestamp);

        vm.expectRevert(IMarketFactory.ReferenceUpdateRequired.selector);
        factory.listDay(address(nvda), FRI, empty);

        bytes[] memory u = _pythUpdate(NVDA_PRICE, 9_000_000, -8, nowTs);
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.InsufficientFee.selector, 1));
        factory.listDay(address(nvda), FRI, u);

        u = _pythUpdate(NVDA_PRICE, 9_000_000, -8, nowTs - 121);
        vm.expectRevert(PythErrors.PriceFeedNotFoundWithinRange.selector);
        factory.listDay{value: 1}(address(nvda), FRI, u);

        u = _pythUpdate(NVDA_PRICE, uint64(uint64(NVDA_PRICE) * 51 / 10_000), -8, nowTs);
        vm.expectRevert(IMarketFactory.ReferenceConfidenceTooWide.selector);
        factory.listDay{value: 1}(address(nvda), FRI, u);

        u = _pythUpdate(-1, 0, -8, nowTs);
        vm.expectRevert(IMarketFactory.BadReferencePrice.selector);
        factory.listDay{value: 1}(address(nvda), FRI, u);
    }

    function test_refusal_wrongPythFeedId() public {
        MockPythWrongId wrong = new MockPythWrongId(keccak256("other"));
        _deployCore(address(wrong));
        _seedCalendar();
        _setNvda(PYTH_ID, true, BUDGET);
        vm.warp(FRI_OPEN - 3 hours);
        bytes[] memory u = new bytes[](1);
        vm.expectRevert(abi.encodeWithSelector(IMarketFactory.WrongFeed.selector, keccak256("other")));
        factory.listDay{value: 1}(address(nvda), FRI, u);
    }

    // ---------- snapshots and locks ----------

    function test_snapshot_unaffectedByLaterEdits() public {
        _listFri();
        _setNvda(keccak256("test:NVDA:v2"), true, BUDGET);
        IMarketFactory.DayInfo memory info = factory.dayInfo(address(nvda), FRI);
        assertEq(info.pythId, PYTH_ID);
        assertEq(info.closeTs, FRI_CLOSE);
    }

    function test_calendarLocksListedDay() public {
        _listFri();
        uint32[] memory d = new uint32[](1);
        IExchangeCalendar.Session[] memory s = new IExchangeCalendar.Session[](1);
        (d[0], s[0]) = (FRI, IExchangeCalendar.Session(FRI_OPEN, FRI_OPEN + 12_600));
        vm.prank(timelock);
        vm.expectRevert(abi.encodeWithSelector(IExchangeCalendar.DayLocked.selector, FRI));
        calendar.setSessions(d, s);
    }

    // ---------- fuzz ----------

    function testFuzz_strikesFollowStrikeMath(int64 price) public {
        price = int64(bound(price, 1e8, 1e12)); // $1 – $10,000
        vm.warp(FRI_OPEN - 3 hours);
        address[] memory m = _listWithPyth(FRI, price);
        (int16[] memory bps,,) = factory.template();
        int64[] memory expected = StrikeMath.positional(price, bps, TICK);
        for (uint256 i; i < bps.length; ++i) {
            if (expected[i] == 0) {
                assertEq(m[i], address(0));
            } else {
                assertEq(MockMarket(m[i]).config().edges[0], expected[i]);
            }
        }
    }
}
