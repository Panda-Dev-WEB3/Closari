// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../src/LMSRMarket.sol";
import {ILMSRMarket} from "../src/interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "../src/interfaces/IMarketFactory.sol";
import {Constants} from "../src/lib/Constants.sol";
import {PriorMath} from "../src/lib/PriorMath.sol";
import {MockStaking} from "./mocks/MockStaking.sol";
import {MarketFixture} from "./utils/MarketFixture.sol";
import {ISignatureTransfer} from "permit2/ISignatureTransfer.sol";
import {LibClone} from "solady/utils/LibClone.sol";

contract LMSRMarketTest is MarketFixture {
    LMSRMarket m;

    function setUp() public override {
        super.setUp();
        m = _market(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
    }

    // ---------------------------------------------------------------- init

    function test_init_implementationLocked() public {
        ILMSRMarket.Config memory c = _config(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        vm.expectRevert(ILMSRMarket.AlreadyInitialized.selector);
        impl.initialize(c, address(pool), oracle, router, address(0));
    }

    function test_init_once() public {
        ILMSRMarket.Config memory c = _config(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        vm.expectRevert(ILMSRMarket.AlreadyInitialized.selector);
        m.initialize(c, address(pool), oracle, router, address(0));
    }

    function test_init_recordsCallerAsFactory_andConfig() public view {
        assertEq(m.factory(), address(this));
        ILMSRMarket.Config memory c = m.config();
        assertEq(c.n, 2);
        assertEq(c.priorWad[0], 5e17);
        assertEq(c.baseFeeBps, 50);
        assertEq(m.cash(), BUDGET);
        assertEq(m.liability(), 0);
        assertEq(uint8(m.state()), uint8(ILMSRMarket.State.Trading));
    }

    function test_init_rejectsBadConfig() public {
        LMSRMarket c2 = LMSRMarket(_clone());
        ILMSRMarket.Config memory c = _config(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        c.priorWad[0] += 1; // Σ ≠ 1e18
        vm.expectRevert(ILMSRMarket.BadConfig.selector);
        c2.initialize(c, address(pool), oracle, router, address(0));
        c = _config(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        c.baseFeeBps = 201;
        vm.expectRevert(ILMSRMarket.BadConfig.selector);
        c2.initialize(c, address(pool), oracle, router, address(0));
    }

    function test_init_pricesEqualPrior() public {
        uint256[] memory prior = new uint256[](5);
        (prior[0], prior[1], prior[2], prior[3], prior[4]) = (2e16, 18e16, 5e17, 28e16, 2e16);
        LMSRMarket r = _market(IMarketFactory.Kind.RANGE, prior, BUDGET);
        uint256[] memory p = r.prices();
        for (uint256 i; i < 5; ++i) {
            assertApproxEqAbs(p[i], prior[i], 1e6); // 1e-12
        }
    }

    // ---------------------------------------------------------------- trading

    function test_buy_paysCostPlusFee_creditsShares_marks() public {
        (uint256 gross, uint256 fee) = m.quoteBuy(1, 100e6, alice);
        uint256 before = usdg.balanceOf(alice);
        uint256 total = _buy(m, alice, 1, 100e6);
        assertEq(total, gross + fee);
        assertEq(fee, (gross * 50 + 9_999) / 10_000);
        assertEq(before - usdg.balanceOf(alice), total);
        assertEq(m.shares(alice, 1), 100e6);
        assertEq(m.cash(), BUDGET + gross);
        assertEq(m.feeEscrow(), fee);
        assertEq(m.feesPaid(alice), fee);
        assertEq(m.liability(), 100e6);
        assertEq(pool.worst(address(m)), int256(m.cash() - 100e6));
        assertEq(pool.best(address(m)), int256(m.cash()));
        assertGt(m.prices()[1], 5e17);
    }

    function test_sell_paysNetToSeller() public {
        _buy(m, alice, 1, 100e6);
        (uint256 gross, uint256 fee) = m.quoteSell(1, 40e6, alice);
        uint256 before = usdg.balanceOf(alice);
        uint256 net = _sell(m, alice, 1, 40e6);
        assertEq(net, gross - fee);
        assertEq(usdg.balanceOf(alice) - before, net);
        assertEq(m.shares(alice, 1), 60e6);
    }

    function test_sell_moreThanHeld_reverts() public {
        _buy(m, alice, 1, 10e6);
        vm.prank(alice);
        vm.expectRevert(ILMSRMarket.InsufficientShares.selector);
        m.sell(1, 11e6, 0, type(uint64).max, address(0));
    }

    function test_slippageAndDeadline() public {
        (uint256 gross, uint256 fee) = m.quoteBuy(0, 50e6, alice);
        vm.prank(alice);
        vm.expectRevert(ILMSRMarket.Slippage.selector);
        m.buy(0, 50e6, gross + fee - 1, type(uint64).max, address(0));
        vm.prank(alice);
        vm.expectRevert(ILMSRMarket.Expired.selector);
        m.buy(0, 50e6, type(uint256).max, uint64(block.timestamp - 1), address(0));
        _buy(m, alice, 0, 50e6);
        (gross, fee) = m.quoteSell(0, 50e6, alice);
        vm.prank(alice);
        vm.expectRevert(ILMSRMarket.Slippage.selector);
        m.sell(0, 50e6, gross - fee + 1, type(uint64).max, address(0));
    }

    function test_badOutcome_zeroShares_tooLarge_clamp() public {
        vm.startPrank(alice);
        vm.expectRevert(ILMSRMarket.BadOutcome.selector);
        m.buy(2, 1e6, type(uint256).max, type(uint64).max, address(0));
        vm.expectRevert(ILMSRMarket.ZeroShares.selector);
        m.buy(0, 0, type(uint256).max, type(uint64).max, address(0));
        uint256 b = m.config().bWad / 1e12;
        vm.expectRevert(ILMSRMarket.TradeTooLarge.selector);
        m.buy(0, 20 * b + 1, type(uint256).max, type(uint64).max, address(0));
        vm.expectRevert(ILMSRMarket.PriceOutOfBounds.selector);
        m.buy(0, 8 * b, type(uint256).max, type(uint64).max, address(0)); // p → ~0.9997 > 0.999
        vm.stopPrank();
    }

    function test_builderAttribution() public {
        vm.prank(alice);
        m.buy(0, 10e6, type(uint256).max, type(uint64).max, builder);
        assertEq(m.feesByBuilder(builder), m.feeEscrow());
        assertEq(m.builderFeesTotal(), m.feeEscrow());
    }

    // ---------------------------------------------------------------- fees

    /// @dev The exact rational fee, rounded once, up (M2 spec §5): base·(1e4 − d)/1e4 + rampMax·elapsed/1800 bps.
    function _feeExact(uint256 g, uint256 base, uint256 d, uint256 rampMax, uint256 elapsed)
        internal
        pure
        returns (uint256)
    {
        uint256 num = base * (10_000 - d) * 1_800 + rampMax * elapsed * 10_000;
        uint256 den = uint256(10_000) * 10_000 * 1_800;
        return (g * num + den - 1) / den;
    }

    function test_ramp_shapeAndCap() public {
        (uint256 g0, uint256 f0) = m.quoteBuy(0, 100e6, alice);
        assertEq(f0, (g0 * 50 + 9_999) / 10_000);
        assertEq(f0, _feeExact(g0, 50, 0, 250, 0));
        vm.warp(HALT - 1_800); // the ramp's first second still charges base only
        (uint256 gs, uint256 fs) = m.quoteBuy(0, 100e6, alice);
        assertEq(fs, _feeExact(gs, 50, 0, 250, 0));
        vm.warp(HALT - 900); // halfway through the ramp: 50 + 125
        (uint256 g1, uint256 f1) = m.quoteBuy(0, 100e6, alice);
        assertEq(f1, (g1 * 175 + 9_999) / 10_000);
        vm.warp(HALT - 1);
        (uint256 g2, uint256 f2) = m.quoteBuy(0, 100e6, alice);
        assertEq(f2, _feeExact(g2, 50, 0, 250, 1_799)); // 50 + 250·1799/1800 bps, not floored to 299
        assertGt(f2, (g2 * 299 + 9_999) / 10_000);
    }

    function test_discount_baseOnly_I15() public {
        stakingMock.set(alice, 3_000);
        (uint256 g, uint256 f) = m.quoteBuy(0, 100e6, alice);
        assertEq(f, (g * 35 + 9_999) / 10_000);
        assertEq(f, _feeExact(g, 50, 3_000, 250, 0));
        vm.warp(HALT - 900);
        (g, f) = m.quoteBuy(0, 100e6, alice);
        assertEq(f, (g * (35 + 125) + 9_999) / 10_000); // ramp never discounted
        assertEq(f, _feeExact(g, 50, 3_000, 250, 900));
    }

    /// A 1-bp discount on a 50-bp base charges 49.995 bps, rounded up once: never 49 bps (no 1-bp jump).
    function test_discount_oneBp_noFloorJump() public {
        stakingMock.set(alice, 1);
        (uint256 g, uint256 f) = m.quoteBuy(0, 100e6, alice);
        (uint256 g0, uint256 f0) = m.quoteBuy(0, 100e6, bob); // bob holds no discount
        assertEq(g, g0);
        assertEq(f, _feeExact(g, 50, 1, 250, 0));
        assertGe(f * 10_000_000, g * 49_995); // ≥ the exact 49.995-bp value
        assertGt(f, (g * 49 + 9_999) / 10_000); // strictly above a floored 49-bp rate
        assertLe(f0 - f, g * 5 / 10_000_000 + 1); // the discount is worth 0.005 bp, not 1 bp
        // the same holds on the sell side, which shares `_fee`
        _buy(m, alice, 0, 100e6);
        (uint256 gs, uint256 fsell) = m.quoteSell(0, 50e6, alice);
        assertEq(fsell, _feeExact(gs, 50, 1, 250, 0));
        uint256 escrow = m.feeEscrow();
        _sell(m, alice, 0, 50e6);
        assertEq(m.feeEscrow() - escrow, fsell);
    }

    function test_discount_brokenStakingIsZero() public {
        stakingMock.set(alice, 3_000);
        MockStaking.Mode[3] memory modes = [MockStaking.Mode.Revert, MockStaking.Mode.BurnGas, MockStaking.Mode.Garbage];
        for (uint256 i; i < 3; ++i) {
            stakingMock.setMode(modes[i]);
            (uint256 g, uint256 f) = m.quoteBuy(0, 100e6, alice);
            assertEq(f, (g * 50 + 9_999) / 10_000);
        }
        stakingMock.setMode(MockStaking.Mode.Normal);
        stakingMock.set(alice, 3_001); // above the cap → 0
        (uint256 g2, uint256 f2) = m.quoteBuy(0, 100e6, alice);
        assertEq(f2, (g2 * 50 + 9_999) / 10_000);
    }

    // ---------------------------------------------------------------- guards

    function test_trade_reverts_atHalt_I7() public {
        _buy(m, alice, 0, 10e6);
        vm.warp(HALT);
        vm.prank(alice);
        vm.expectRevert(ILMSRMarket.Halted.selector);
        m.buy(0, 1e6, type(uint256).max, type(uint64).max, address(0));
        vm.prank(alice);
        vm.expectRevert(ILMSRMarket.Halted.selector);
        m.sell(0, 1e6, 0, type(uint64).max, address(0));
    }

    function testFuzz_noTradeAtOrAfterHalt(uint64 t) public {
        t = uint64(bound(t, HALT, HALT + 30 days));
        vm.warp(t);
        vm.prank(alice);
        vm.expectRevert(ILMSRMarket.Halted.selector);
        m.buy(0, 1e6, type(uint256).max, type(uint64).max, address(0));
    }

    function test_trade_reverts_whenCAVisible() public {
        _buy(m, alice, 0, 10e6);
        // 1. multiplier already changed
        token.setMultiplier(2e18);
        _expectCA();
        token.setMultiplier(1e18);
        // 2. pending change effective inside [createdTs, closeTs + CA_AFTER]
        token.schedule(2e18, CLOSE + Constants.CA_AFTER);
        _expectCA();
        token.schedule(2e18, CLOSE + Constants.CA_AFTER + 1); // outside the window: trading allowed
        _buy(m, alice, 0, 1e6);
        token.schedule(1e18, 0); // cancelled
        // 3. oracle paused
        token.setOraclePaused(true);
        _expectCA();
        token.setOraclePaused(false);
        _buy(m, alice, 0, 1e6); // resumes
    }

    function _expectCA() internal {
        vm.prank(alice);
        vm.expectRevert(ILMSRMarket.CorporateActionVisible.selector);
        m.buy(0, 1e6, type(uint256).max, type(uint64).max, address(0));
        vm.prank(alice);
        vm.expectRevert(ILMSRMarket.CorporateActionVisible.selector);
        m.sell(0, 1e6, 0, type(uint64).max, address(0));
    }

    function test_upDown_pausedUntilOpen() public {
        LMSRMarket u = _market(IMarketFactory.Kind.UPDOWN, _uniform(2), BUDGET);
        _buy(u, alice, 0, 10e6); // before the open: fine
        vm.warp(OPEN);
        vm.prank(alice);
        vm.expectRevert(ILMSRMarket.AwaitingOpen.selector);
        u.buy(0, 1e6, type(uint256).max, type(uint64).max, address(0));
        vm.expectRevert(ILMSRMarket.NotOracle.selector);
        u.setOpenReference(18_800_000_000, 1e6);
        vm.prank(oracle);
        u.setOpenReference(18_800_000_000, 1e6);
        assertEq(u.config().edges[0], 18_800_000_000);
        _buy(u, alice, 0, 1e6);
        vm.prank(oracle);
        vm.expectRevert(ILMSRMarket.OpenAlreadySet.selector);
        u.setOpenReference(1, 1);
        vm.prank(oracle);
        vm.expectRevert(ILMSRMarket.NotUpDown.selector);
        m.setOpenReference(1, 1);
    }

    function test_lateHourCap() public {
        uint256 b = m.config().bWad / 1e12;
        vm.warp(CLOSE - 3_600);
        _buy(m, alice, 0, b / 4);
        vm.prank(alice);
        vm.expectRevert(ILMSRMarket.LateHourCap.selector);
        m.buy(0, 1, type(uint256).max, type(uint64).max, address(0));
        _sell(m, alice, 0, 10e6); // selling frees room
        _buy(m, alice, 0, 10e6);
        _buy(m, bob, 0, 1e6); // the cap is per account
    }

    // ---------------------------------------------------------------- M3 stubs

    function test_settlementStubs_revert() public {
        vm.expectRevert(ILMSRMarket.NotYetImplemented.selector);
        m.resolve(0, 1);
        vm.expectRevert(ILMSRMarket.NotYetImplemented.selector);
        m.voidMarket(1);
        vm.expectRevert(ILMSRMarket.NotYetImplemented.selector);
        m.claim(alice);
        vm.expectRevert(ILMSRMarket.NotYetImplemented.selector);
        m.claimMany(new address[](0));
        vm.expectRevert(ILMSRMarket.NotYetImplemented.selector);
        m.sweep();
        vm.expectRevert(ILMSRMarket.NotYetImplemented.selector);
        m.pullFees();
    }

    // ---------------------------------------------------------------- accumulator

    function test_cumulativeAt_flatMarket() public {
        vm.warp(CREATED + 100);
        uint256[] memory c = m.cumulativeAt(CREATED + 100);
        assertEq(c[0], 100 * 5e17);
        assertEq(c[1], 100 * 5e17);
        vm.warp(CREATED + 200);
        _buy(m, alice, 0, 1e6);
        vm.expectRevert(ILMSRMarket.BadTimestamp.selector);
        m.cumulativeAt(CREATED + 150); // before the last trade
    }

    // ---------------------------------------------------------------- extra coverage

    function test_init_rejectsPriorBelowFloor() public {
        LMSRMarket c2 = LMSRMarket(_clone());
        ILMSRMarket.Config memory c = _config(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        c.priorWad[0] = Constants.PRIOR_MIN - 1;
        c.priorWad[1] = 1e18 - c.priorWad[0];
        vm.expectRevert(ILMSRMarket.BadConfig.selector);
        c2.initialize(c, address(pool), oracle, router, address(0));
    }

    function test_setOpenReference_rejectsNonPositivePrice() public {
        LMSRMarket u = _market(IMarketFactory.Kind.UPDOWN, _uniform(2), BUDGET);
        vm.prank(oracle);
        vm.expectRevert(ILMSRMarket.BadConfig.selector);
        u.setOpenReference(0, 1e6);
    }

    function test_zeroFee_noEscrow() public {
        LMSRMarket z = LMSRMarket(_clone());
        ILMSRMarket.Config memory c = _config(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        c.baseFeeBps = 0;
        c.rampMaxBps = 0;
        pool.allocate(address(z), BUDGET);
        usdg.mint(address(z), BUDGET);
        z.initialize(c, address(pool), oracle, router, address(stakingMock));
        usdg.mint(alice, 1_000e6);
        vm.prank(alice);
        usdg.approve(address(z), type(uint256).max);
        _buy(z, alice, 0, 10e6);
        assertEq(z.feeEscrow(), 0);
        assertEq(z.feesPaid(alice), 0);
    }

    function test_noStakingContract_noDiscount() public {
        LMSRMarket z = LMSRMarket(_clone());
        ILMSRMarket.Config memory c = _config(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        pool.allocate(address(z), BUDGET);
        usdg.mint(address(z), BUDGET);
        z.initialize(c, address(pool), oracle, router, address(0));
        (uint256 g, uint256 f) = z.quoteBuy(0, 100e6, alice);
        assertEq(f, (g * 50 + 9_999) / 10_000);
    }

    function test_stakingWithoutCode_noDiscount() public {
        LMSRMarket z = LMSRMarket(_clone());
        ILMSRMarket.Config memory c = _config(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        pool.allocate(address(z), BUDGET);
        usdg.mint(address(z), BUDGET);
        z.initialize(c, address(pool), oracle, router, makeAddr("eoaStaking")); // call succeeds, returns no data
        (uint256 g, uint256 f) = z.quoteBuy(0, 100e6, alice);
        assertEq(f, (g * 50 + 9_999) / 10_000);
    }

    function test_quote_atOrAfterHalt_usesFullRamp() public {
        vm.warp(HALT);
        (uint256 g, uint256 f) = m.quoteBuy(0, 100e6, alice);
        assertEq(f, (g * 300 + 9_999) / 10_000); // base 50 + ramp max 250
    }

    function test_checkpoints_beforeAndAfterTrades() public {
        (uint64[2] memory ts, uint256[][2] memory cum) = m.checkpoints();
        assertEq(ts[0], HALT - Constants.VOID_TWAP_WINDOW);
        assertEq(ts[1], 0); // not an UPDOWN market
        assertEq(cum[1].length, 0);
        assertEq(cum[0].length, 2);
        // a trade after the checkpoint timestamp freezes it
        vm.warp(ts[0] + 10);
        _buy(m, alice, 0, 1e6);
        (, uint256[][2] memory cum2) = m.checkpoints();
        assertEq(cum2[0].length, 2);
        assertEq(cum2[0][0], uint256(ts[0] - CREATED) * 5e17); // flat uniform prior: exact
        assertEq(cum2[0][1], uint256(ts[0] - CREATED) * 5e17);

        LMSRMarket u = _market(IMarketFactory.Kind.UPDOWN, _uniform(2), BUDGET);
        (uint64[2] memory uts,) = u.checkpoints();
        assertGt(uts[1], 0);
    }

    function test_checkpoint_excludesCrossingTradePrice() public {
        (uint64[2] memory ts,) = m.checkpoints();
        uint64 cp = ts[0];
        uint64 t1 = CREATED + 1_000;
        vm.warp(t1);
        _buy(m, alice, 0, 100e6);
        uint256 pAfter = m.prices()[0];
        assertGt(pAfter, 5e17);
        vm.warp(cp + 10);
        _buy(m, bob, 0, 100e6); // crosses the checkpoint
        uint256 pCross = m.prices()[0];
        assertGt(pCross, pAfter);
        (, uint256[][2] memory cum) = m.checkpoints();
        uint256 expected0 = 5e17 * uint256(t1 - CREATED) + pAfter * uint256(cp - t1);
        assertEq(cum[0][0], expected0);
        assertEq(cum[0][1], uint256(cp - CREATED) * 1e18 - expected0);
        // the crossing trade's own price must not leak in
        assertLt(cum[0][0], expected0 + pCross); // sanity: differs from any leaked value
        assertTrue(cum[0][0] != expected0 + (pCross - pAfter) * 10);
    }

    function test_checkpoints_singleRollCrossesBoth_updown() public {
        LMSRMarket u = _market(IMarketFactory.Kind.UPDOWN, _uniform(2), BUDGET);
        (uint64[2] memory ts,) = u.checkpoints();
        assertEq(ts[1], OPEN - Constants.VOID_TWAP_WINDOW);
        assertLt(ts[1], ts[0]);
        vm.warp(ts[0] + 10); // after both checkpoints, before the halt, no trade so far
        vm.prank(oracle);
        u.setOpenReference(18_800_000_000, 1e6); // the first roll crosses both
        _buy(u, alice, 0, 1e6);
        (, uint256[][2] memory cum) = u.checkpoints();
        for (uint256 j; j < 2; ++j) {
            assertEq(cum[j][0], uint256(ts[j] - CREATED) * 5e17);
            assertEq(cum[j][1], uint256(ts[j] - CREATED) * 5e17);
        }
    }

    function _clone() internal returns (address) {
        return LibClone.clone(address(impl));
    }
}
