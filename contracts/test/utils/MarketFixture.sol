// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../../src/LMSRMarket.sol";
import {ILMSRMarket} from "../../src/interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "../../src/interfaces/IMarketFactory.sol";
import {PriorMath} from "../../src/lib/PriorMath.sol";
import {MockHousePool} from "../mocks/MockHousePool.sol";
import {MockStaking} from "../mocks/MockStaking.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {MockUSDG} from "../mocks/MockUSDG.sol";
import {Test} from "forge-std/Test.sol";
import {LibClone} from "solady/utils/LibClone.sol";

abstract contract MarketFixture is Test {
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    uint64 internal constant CREATED = 1_795_160_000; // FRI 2026-11-20, before the 09:30 ET open
    uint64 internal constant OPEN = 1_795_185_000;
    uint64 internal constant CLOSE = 1_795_208_400;
    uint64 internal constant HALT = CLOSE - 600;
    uint96 internal constant BUDGET = 2_000e6;

    MockUSDG internal usdg;
    MockHousePool internal pool;
    MockStaking internal stakingMock;
    MockStockToken internal token;
    LMSRMarket internal impl;
    address internal oracle = makeAddr("oracle");
    address internal router = makeAddr("router");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal builder = makeAddr("builder");

    function setUp() public virtual {
        vm.warp(CREATED);
        usdg = new MockUSDG();
        pool = new MockHousePool();
        stakingMock = new MockStaking();
        token = new MockStockToken(1e18);
        impl = new LMSRMarket(address(usdg), PERMIT2);
    }

    function _uniform(uint256 n) internal pure returns (uint256[] memory) {
        return PriorMath.uniform(n);
    }

    function _config(IMarketFactory.Kind kind, uint256[] memory prior, uint96 budget)
        internal
        view
        returns (ILMSRMarket.Config memory c)
    {
        c.token = address(token);
        c.dayId = 20777;
        c.kind = kind;
        c.n = uint8(prior.length);
        if (kind == IMarketFactory.Kind.ABOVE) {
            c.edges = new int64[](1);
            c.edges[0] = 18_812_000_000;
        } else if (kind == IMarketFactory.Kind.RANGE) {
            c.edges = new int64[](prior.length - 1);
            for (uint256 i; i < c.edges.length; ++i) {
                c.edges[i] = int64(int256(18_000_000_000 + i * 300_000_000));
            }
        }
        c.createdTs = CREATED;
        c.openTs = OPEN;
        c.haltTs = HALT;
        c.closeTs = CLOSE;
        c.multiplierSnapshot = 1e18;
        c.bWad = PriorMath.liquidity(budget, prior) * 1e12;
        c.budget = budget;
        c.priorWad = prior;
        c.baseFeeBps = 50;
        c.rampMaxBps = 250;
    }

    function _market(IMarketFactory.Kind kind, uint256[] memory prior, uint96 budget) internal returns (LMSRMarket m) {
        m = LMSRMarket(LibClone.clone(address(impl)));
        pool.allocate(address(m), budget);
        usdg.mint(address(m), budget); // the pool's allocation sits in the market
        m.initialize(_config(kind, prior, budget), address(pool), oracle, router, address(stakingMock));
        address[3] memory who = [alice, bob, carol];
        for (uint256 i; i < 3; ++i) {
            usdg.mint(who[i], 1_000_000e6);
            vm.prank(who[i]);
            usdg.approve(address(m), type(uint256).max);
        }
    }

    function _buy(LMSRMarket m, address who, uint8 k, uint256 sh) internal returns (uint256 total) {
        vm.prank(who);
        total = m.buy(k, sh, type(uint256).max, type(uint64).max, address(0));
    }

    function _sell(LMSRMarket m, address who, uint8 k, uint256 sh) internal returns (uint256 net) {
        vm.prank(who);
        net = m.sell(k, sh, 0, type(uint64).max, address(0));
    }
}
