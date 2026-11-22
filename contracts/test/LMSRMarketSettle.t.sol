// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../src/LMSRMarket.sol";
import {ILMSRMarket} from "../src/interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "../src/interfaces/IMarketFactory.sol";
import {MarketFixture} from "./utils/MarketFixture.sol";

/// @dev In MarketFixture the test contract calls initialize, so it is the market's `factory` (guardian path).
contract LMSRMarketSettleTest is MarketFixture {
    uint8 internal constant TIE = 3;
    uint8 internal constant NO_OPEN = 7;
    uint8 internal constant GUARDIAN = 9;

    LMSRMarket internal m; // ABOVE, uniform prior
    LMSRMarket internal u; // UPDOWN

    function setUp() public override {
        super.setUp();
        m = _market(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        u = _market(IMarketFactory.Kind.UPDOWN, _uniform(2), BUDGET);
    }

    function _vOf(LMSRMarket x) internal view returns (uint256[] memory v) {
        (,, v) = x.finalInfo();
    }

    // ------------------------------------------------------------ access and timing

    function test_resolve_access() public {
        vm.warp(CLOSE);
        vm.expectRevert(ILMSRMarket.NotOracle.selector);
        m.resolve(1, 1);
        vm.warp(CLOSE - 1);
        vm.prank(oracle);
        vm.expectRevert(ILMSRMarket.TooEarly.selector);
        m.resolve(1, 1);
        vm.warp(CLOSE);
        vm.prank(oracle);
        vm.expectRevert(ILMSRMarket.BadOutcome.selector);
        m.resolve(2, 1);
        vm.prank(oracle);
        m.resolve(1, 18_900_000_000);
        vm.prank(oracle);
        vm.expectRevert(ILMSRMarket.NotTrading.selector);
        m.resolve(1, 1);
        vm.prank(oracle);
        vm.expectRevert(ILMSRMarket.NotTrading.selector);
        m.voidMarket(TIE);
    }

    function test_voidMarket_access() public {
        vm.warp(HALT);
        vm.prank(oracle);
        vm.expectRevert(ILMSRMarket.NotFactory.selector);
        m.voidMarket(GUARDIAN);
        vm.expectRevert(ILMSRMarket.NotOracle.selector);
        m.voidMarket(TIE); // the factory (this contract) may only use GUARDIAN
        vm.startPrank(oracle);
        vm.expectRevert(ILMSRMarket.BadReason.selector);
        m.voidMarket(0);
        vm.expectRevert(ILMSRMarket.BadReason.selector);
        m.voidMarket(10);
        vm.expectRevert(ILMSRMarket.BadReason.selector);
        m.voidMarket(NO_OPEN); // ABOVE has no open
        vm.stopPrank();
        vm.warp(HALT - 1);
        vm.prank(oracle);
        vm.expectRevert(ILMSRMarket.TooEarly.selector);
        m.voidMarket(TIE);
        vm.warp(OPEN - 1);
        vm.prank(oracle);
        vm.expectRevert(ILMSRMarket.TooEarly.selector);
        u.voidMarket(NO_OPEN);
        vm.warp(HALT);
        vm.expectRevert(ILMSRMarket.Halted.selector);
        m.voidMarket(GUARDIAN);
    }

    function test_noOpen_rejectedOnceOpenRecorded() public {
        vm.warp(OPEN);
        vm.prank(oracle);
        u.setOpenReference(18_800_000_000, 1e6);
        vm.warp(HALT);
        vm.prank(oracle);
        vm.expectRevert(ILMSRMarket.BadReason.selector);
        u.voidMarket(NO_OPEN);
    }

    // ------------------------------------------------------------ resolve state

    function test_resolve_reserveIsWinningShares() public {
        _buy(m, alice, 1, 100e6);
        _buy(m, bob, 0, 40e6);
        _buy(m, carol, 1, 25e6);
        vm.warp(CLOSE);
        vm.prank(oracle);
        m.resolve(1, 18_900_000_000);
        assertEq(uint8(m.state()), uint8(ILMSRMarket.State.Resolved));
        assertEq(m.liability(), 125e6);
        (uint8 w, uint8 r, uint256[] memory v) = m.finalInfo();
        assertEq(w, 1);
        assertEq(r, 0);
        assertEq(v.length, 0);
    }

    // ------------------------------------------------------------ void windows

    function test_void_haltWindow() public {
        vm.warp(HALT - 1800);
        _buy(m, alice, 1, 500e6);
        vm.warp(HALT + 10);
        (uint64[2] memory ts, uint256[][2] memory cp) = m.checkpoints();
        uint256[] memory c1 = m.cumulativeAt(HALT);
        uint256 w = HALT - ts[0];
        vm.prank(oracle);
        m.voidMarket(TIE);
        uint256[] memory v = _vOf(m);
        assertEq(v[0], (c1[0] - cp[0][0]) / w);
        assertEq(v[1], (c1[1] - cp[0][1]) / w);
        assertGt(v[1], 5e17); // the push held for 30 of the 60 minutes
        assertLe(v[0] + v[1], 1e18);
        assertEq(m.liability(), (500e6 * v[1] + 1e18 - 1) / 1e18); // ceil(t·v)
    }

    function test_void_upDownWithoutOpen_usesOpenWindow_anyReason() public {
        vm.warp(OPEN - 1800);
        _buy(u, alice, 1, 300e6);
        vm.warp(HALT);
        (uint64[2] memory ts, uint256[][2] memory cp) = u.checkpoints();
        uint256[] memory c1 = u.cumulativeAt(OPEN);
        uint256 w = OPEN - ts[1];
        vm.prank(oracle);
        u.voidMarket(TIE); // a day-level reason, but the market has no open: window ends at openTs
        uint256[] memory v = _vOf(u);
        assertEq(v[1], (c1[1] - cp[1][1]) / w);
        assertEq(v[0], (c1[0] - cp[1][0]) / w);
    }

    function test_guardian_lifetimeWindow() public {
        vm.warp(CREATED + 1000);
        _buy(m, alice, 1, 500e6);
        vm.warp(CREATED + 4000);
        uint256[] memory c1 = m.cumulativeAt(CREATED + 4000);
        m.voidMarket(GUARDIAN);
        uint256[] memory v = _vOf(m);
        assertEq(v[1], c1[1] / 4000);
        assertEq(v[0], c1[0] / 4000);
        (, uint8 r,) = m.finalInfo();
        assertEq(r, GUARDIAN);
    }

    function test_guardian_zeroLengthWindow_usesPrior() public {
        uint256[] memory prior = new uint256[](2);
        (prior[0], prior[1]) = (3e17, 7e17);
        LMSRMarket p = _market(IMarketFactory.Kind.ABOVE, prior, BUDGET);
        _buy(p, alice, 1, 500e6); // same second as creation: zero weight in any TWAP
        p.voidMarket(GUARDIAN);
        uint256[] memory v = _vOf(p);
        assertEq(v[0], 3e17);
        assertEq(v[1], 7e17);
    }

    function test_guardian_upDownAfterOpenWithoutOpen_usesOpenWindow() public {
        vm.warp(OPEN - 600);
        _buy(u, alice, 0, 200e6);
        vm.warp(OPEN + 900);
        (uint64[2] memory ts, uint256[][2] memory cp) = u.checkpoints();
        uint256[] memory c1 = u.cumulativeAt(OPEN);
        u.voidMarket(GUARDIAN);
        uint256[] memory v = _vOf(u);
        assertEq(v[0], (c1[0] - cp[1][0]) / (OPEN - ts[1]));
    }

    function testFuzz_voidPrices_sumAtMostOne(uint256 s1, uint256 s2, uint256 dt) public {
        LMSRMarket r = _market(IMarketFactory.Kind.RANGE, _uniform(4), BUDGET);
        vm.warp(HALT - 3000);
        _buy(r, alice, 1, bound(s1, 1e6, 300e6)); // inside the last hour: ≤ b/4 ≈ 360 shares per account
        vm.warp(HALT - bound(dt, 1, 2000));
        _buy(r, bob, 3, bound(s2, 1e6, 300e6));
        vm.warp(HALT);
        vm.prank(oracle);
        r.voidMarket(TIE);
        uint256[] memory v = _vOf(r);
        assertLe(v[0] + v[1] + v[2] + v[3], 1e18);
        assertLe(r.liability(), r.cash());
    }
}
