// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ExchangeCalendar} from "../../src/ExchangeCalendar.sol";
import {MarketFactory} from "../../src/MarketFactory.sol";
import {StockTokenAllowList} from "../../src/StockTokenAllowList.sol";
import {IExchangeCalendar} from "../../src/interfaces/IExchangeCalendar.sol";
import {ISettlementOracle} from "../../src/interfaces/ISettlementOracle.sol";
import {IStockTokenAllowList} from "../../src/interfaces/IStockTokenAllowList.sol";
import {MockAggregator} from "../mocks/MockAggregator.sol";
import {MockBeacon} from "../mocks/MockBeacon.sol";
import {MockFeeRouter} from "../mocks/MockFeeRouter.sol";
import {MockHousePool} from "../mocks/MockHousePool.sol";
import {MockMarket} from "../mocks/MockMarket.sol";
import {MockSettlementOracle} from "../mocks/MockSettlementOracle.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {MockPyth} from "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import {Test} from "forge-std/Test.sol";

abstract contract Fixture is Test {
    // ET trading days (dayId = days since 1970-01-01), EST (UTC−5). Computed with Intl on 2026-11-21.
    uint32 internal constant THU = 20776; // 2026-11-19
    uint32 internal constant FRI = 20777; // 2026-11-20
    uint32 internal constant SAT = 20778;
    uint32 internal constant MON = 20780; // 2026-11-23
    uint32 internal constant TUE = 20781;
    uint64 internal constant THU_OPEN = 1_795_098_600;
    uint64 internal constant THU_CLOSE = 1_795_122_000;
    uint64 internal constant FRI_OPEN = 1_795_185_000;
    uint64 internal constant FRI_CLOSE = 1_795_208_400;
    uint64 internal constant MON_OPEN = 1_795_444_200;
    uint64 internal constant MON_CLOSE = 1_795_467_600;
    uint64 internal constant TUE_OPEN = 1_795_530_600;
    uint64 internal constant TUE_CLOSE = 1_795_554_000;

    bytes32 internal constant PYTH_ID = keccak256("test:NVDA");
    uint96 internal constant BUDGET = 2_000e6;
    uint32 internal constant TICK = 50_000_000;
    int64 internal constant NVDA_PRICE = 18_812_000_000; // $188.12 (Overview example 1)

    address internal timelock = makeAddr("timelock");
    address internal guardian = makeAddr("guardian");
    address internal lister = makeAddr("lister");
    address internal staking = makeAddr("staking");

    MockBeacon internal beacon;
    MockStockToken internal nvda;
    MockAggregator internal feed;
    MockPyth internal pyth;
    MockHousePool internal pool;
    MockSettlementOracle internal oracle;
    MockFeeRouter internal router;
    MockMarket internal marketImpl;
    ExchangeCalendar internal calendar;
    StockTokenAllowList internal allowList;
    MarketFactory internal factory;

    function setUp() public virtual {
        vm.warp(THU_OPEN - 3 hours);
        beacon = new MockBeacon(makeAddr("implementation"));
        nvda = new MockStockToken(1e18);
        feed = new MockAggregator(8, "RHNVDA / USD");
        pyth = new MockPyth(120, 1);
        pool = new MockHousePool();
        oracle = new MockSettlementOracle();
        router = new MockFeeRouter();
        marketImpl = new MockMarket();
        _deployCore(address(pyth));
        _seedCalendar();
        _setNvda(PYTH_ID, true, BUDGET);
        vm.deal(lister, 1 ether);
    }

    /// @dev Calendar needs the factory address and the factory needs the calendar: predict by nonce.
    function _deployCore(address pyth_) internal {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);
        calendar = new ExchangeCalendar(timelock, predicted);
        allowList = new StockTokenAllowList(address(beacon), address(nvda).codehash, timelock);
        factory = new MarketFactory(
            MarketFactory.Params({
                calendar: address(calendar),
                allowList: address(allowList),
                pool: address(pool),
                oracle: address(oracle),
                router: address(router),
                staking: staking,
                pyth: pyth_,
                marketImpl: address(marketImpl),
                timelock: timelock,
                guardian: guardian
            })
        );
        require(address(factory) == predicted, "factory address prediction");
    }

    function _seedCalendar() internal {
        uint32[] memory d = new uint32[](4);
        IExchangeCalendar.Session[] memory s = new IExchangeCalendar.Session[](4);
        (d[0], s[0]) = (THU, IExchangeCalendar.Session(THU_OPEN, THU_CLOSE));
        (d[1], s[1]) = (FRI, IExchangeCalendar.Session(FRI_OPEN, FRI_CLOSE));
        (d[2], s[2]) = (MON, IExchangeCalendar.Session(MON_OPEN, MON_CLOSE));
        (d[3], s[3]) = (TUE, IExchangeCalendar.Session(TUE_OPEN, TUE_CLOSE));
        vm.prank(timelock);
        calendar.setSessions(d, s);
    }

    function _setNvda(bytes32 pythId, bool listed, uint96 budget) internal {
        vm.prank(timelock);
        allowList.setAsset(
            address(nvda),
            IStockTokenAllowList.Asset({
                pythId: pythId,
                clFeed: address(feed),
                tickPrice8: TICK,
                budgetAbove: budget,
                budgetRange: budget,
                budgetUpDown: budget,
                volBps: 300,
                listed: listed
            })
        );
    }

    function _pythUpdate(int64 price, uint64 conf, int32 expo, uint64 publishTime)
        internal
        view
        returns (bytes[] memory u)
    {
        u = new bytes[](1);
        u[0] = pyth.createPriceFeedUpdateData(PYTH_ID, price, conf, expo, price, conf, publishTime, publishTime - 1);
    }

    /// @dev Confidence 0.1% of price (inside the 0.5% listing bound at any price).
    function _updateNow(int64 price) internal view returns (bytes[] memory) {
        uint64 conf = price > 0 ? uint64(price) / 1_000 : 0;
        return _pythUpdate(price, conf, -8, uint64(block.timestamp));
    }

    /// @dev Build the update BEFORE any vm.expectEmit: the helper's call to MockPyth would otherwise be "the next call".
    function _listWith(uint32 dayId, bytes[] memory u) internal returns (address[] memory) {
        vm.prank(lister);
        return factory.listDay{value: 1}(address(nvda), dayId, u);
    }

    function _listWithPyth(uint32 dayId, int64 price) internal returns (address[] memory) {
        return _listWith(dayId, _updateNow(price));
    }

    function _listFri() internal returns (address[] memory) {
        vm.warp(FRI_OPEN - 3 hours);
        return _listWithPyth(FRI, NVDA_PRICE);
    }

    function _finalClose(uint32 dayId, int64 price8, ISettlementOracle.VoidReason v) internal {
        oracle.setCloseResult(
            address(nvda),
            dayId,
            ISettlementOracle.PriceResult({
                price8: price8,
                conf8: 0,
                publishTime: 0,
                tier: ISettlementOracle.Tier.A,
                firstSubmitTs: 0,
                final_: true,
                dayVoid: v
            })
        );
    }
}
