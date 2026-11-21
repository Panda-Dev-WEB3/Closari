// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../src/LMSRMarket.sol";
import {IMarketFactory} from "../src/interfaces/IMarketFactory.sol";
import {Constants} from "../src/lib/Constants.sol";
import {MockStockToken} from "./mocks/MockStockToken.sol";
import {MockUSDG} from "./mocks/MockUSDG.sol";
import {MarketFixture} from "./utils/MarketFixture.sol";
import {Test} from "forge-std/Test.sol";

contract MarketHandler is Test {
    LMSRMarket public m;
    MockUSDG public usdg;
    MockStockToken public token;
    address[8] internal actors;
    uint64 public halt;
    bool public tradedAtOrAfterHalt;

    constructor(LMSRMarket m_, MockUSDG usdg_, MockStockToken token_, uint64 halt_) {
        (m, usdg, token, halt) = (m_, usdg_, token_, halt_);
        for (uint256 i; i < 8; ++i) {
            actors[i] = address(uint160(0x1000 + i));
            usdg.mint(actors[i], 10_000_000e6);
            vm.prank(actors[i]);
            usdg.approve(address(m), type(uint256).max);
        }
    }

    function buy(uint256 a, uint8 k, uint256 sh) external {
        address who = actors[a % 8];
        k = uint8(bound(k, 0, m.config().n - 1));
        sh = bound(sh, 1, 2 * (m.config().bWad / 1e12));
        vm.prank(who);
        try m.buy(k, sh, type(uint256).max, type(uint64).max, address(0)) {
            if (block.timestamp >= halt) tradedAtOrAfterHalt = true;
        } catch {}
    }

    function sell(uint256 a, uint8 k, uint256 sh) external {
        address who = actors[a % 8];
        k = uint8(bound(k, 0, m.config().n - 1));
        uint256 held = m.shares(who, k);
        if (held == 0) return;
        sh = bound(sh, 1, held);
        vm.prank(who);
        try m.sell(k, sh, 0, type(uint64).max, address(0)) {
            if (block.timestamp >= halt) tradedAtOrAfterHalt = true;
        } catch {}
    }

    function warp(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 0, 2 hours));
    }

    function toggleCA(bool on) external {
        token.setOraclePaused(on);
    }

    function sumShares(uint8 k) external view returns (uint256 s) {
        for (uint256 i; i < 8; ++i) {
            s += m.shares(actors[i], k);
        }
    }
}

contract LMSRMarketInvariantTest is MarketFixture {
    LMSRMarket m;
    MarketHandler h;

    function setUp() public override {
        super.setUp();
        uint256[] memory prior = new uint256[](5);
        (prior[0], prior[1], prior[2], prior[3], prior[4]) = (5e16, 2e17, 5e17, 2e17, 5e16);
        m = _market(IMarketFactory.Kind.RANGE, prior, BUDGET);
        h = new MarketHandler(m, usdg, token, HALT);
        targetContract(address(h));
    }

    function invariant_I1prime_cashCoversLiability() public view {
        assertGe(m.cash(), m.liability());
    }

    function invariant_I2_balanceCoversCashAndFees() public view {
        assertGe(usdg.balanceOf(address(m)), m.cash() + m.feeEscrow());
    }

    function invariant_I3_pricesInClamp() public view {
        uint256[] memory p = m.prices();
        uint256 s;
        for (uint256 i; i < p.length; ++i) {
            assertGe(p[i], Constants.P_MIN);
            assertLe(p[i], 1e18 - Constants.P_MIN);
            s += p[i];
        }
        assertLe(s, 1e18);
    }

    function invariant_I7_noTradeAfterHalt() public view {
        assertFalse(h.tradedAtOrAfterHalt());
    }

    function invariant_marksMatchPool() public view {
        uint256 hi;
        uint256 lo = type(uint256).max;
        for (uint8 k; k < 5; ++k) {
            uint256 t = h.sumShares(k);
            if (t > hi) hi = t;
            if (t < lo) lo = t;
        }
        assertEq(hi, m.liability());
        assertEq(pool.worst(address(m)), int256(m.cash() - hi));
        assertEq(pool.best(address(m)), int256(m.cash() - lo));
    }
}
