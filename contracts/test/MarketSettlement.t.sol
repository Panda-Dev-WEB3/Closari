// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../src/LMSRMarket.sol";
import {ILMSRMarket} from "../src/interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "../src/interfaces/IMarketFactory.sol";
import {Constants} from "../src/lib/Constants.sol";
import {MarketSettlement} from "../src/lib/MarketSettlement.sol";
import {MarketFixture} from "./utils/MarketFixture.sol";
import {LibClone} from "solady/utils/LibClone.sol";

contract MarketSettlementTest is MarketFixture {
    function _fresh() internal returns (LMSRMarket) {
        return LMSRMarket(LibClone.clone(address(impl)));
    }

    function _bad(ILMSRMarket.Config memory c) internal {
        LMSRMarket m = _fresh();
        vm.expectRevert(ILMSRMarket.BadConfig.selector);
        m.initialize(c, address(pool), oracle, router, address(stakingMock));
    }

    function _ok(ILMSRMarket.Config memory c) internal {
        _fresh().initialize(c, address(pool), oracle, router, address(stakingMock));
    }

    function test_validate_acceptsEachKind() public {
        _ok(_config(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET));
        _ok(_config(IMarketFactory.Kind.RANGE, _uniform(5), BUDGET));
        _ok(_config(IMarketFactory.Kind.UPDOWN, _uniform(2), BUDGET));
    }

    function test_validate_tokenZero() public {
        ILMSRMarket.Config memory c = _config(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        c.token = address(0);
        _bad(c);
    }

    function test_validate_bRange() public {
        ILMSRMarket.Config memory c = _config(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        c.bWad = Constants.B_MIN * 1e12 - 1;
        _bad(c);
        c.bWad = Constants.B_MAX * 1e12 + 1;
        c.budget = type(uint96).max; // so only the range check can fail
        _bad(c);
    }

    function test_validate_lossBound() public {
        ILMSRMarket.Config memory c = _config(IMarketFactory.Kind.RANGE, _uniform(4), BUDGET);
        _ok(c); // the factory mapping passes
        c.bWad = c.bWad * 2; // b·ln(1/p_min) now exceeds the budget
        _bad(c);
    }

    function test_validate_edgesPerKind() public {
        ILMSRMarket.Config memory c = _config(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        c.edges = new int64[](2);
        (c.edges[0], c.edges[1]) = (1, 2);
        _bad(c); // ABOVE needs exactly one edge
        c = _config(IMarketFactory.Kind.ABOVE, _uniform(3), BUDGET);
        _bad(c); // ABOVE needs n == 2
        c = _config(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        c.edges[0] = 0;
        _bad(c); // edges are positive
        c = _config(IMarketFactory.Kind.RANGE, _uniform(4), BUDGET);
        c.edges = new int64[](2);
        (c.edges[0], c.edges[1]) = (1, 2);
        _bad(c); // RANGE needs n − 1 edges
        c = _config(IMarketFactory.Kind.RANGE, _uniform(4), BUDGET);
        c.edges[2] = c.edges[1];
        _bad(c); // strictly increasing
        c = _config(IMarketFactory.Kind.UPDOWN, _uniform(2), BUDGET);
        c.edges = new int64[](1);
        c.edges[0] = 1;
        _bad(c); // UPDOWN has no edge before the open
        c = _config(IMarketFactory.Kind.UPDOWN, _uniform(3), BUDGET);
        _bad(c); // UPDOWN needs n == 2
    }

    function test_validate_upDownTimes() public {
        ILMSRMarket.Config memory c = _config(IMarketFactory.Kind.UPDOWN, _uniform(2), BUDGET);
        c.openTs = c.createdTs;
        _bad(c);
        c.openTs = c.haltTs;
        _bad(c);
    }

    function test_validate_haltAfterRampWindow() public {
        ILMSRMarket.Config memory c = _config(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        (c.createdTs, c.openTs, c.haltTs, c.closeTs) = (1, 2, uint64(Constants.RAMP_WINDOW), 2_400);
        _bad(c);
    }

    function test_voidPrices_windowAndZeroWindow() public pure {
        uint256[] memory c0 = new uint256[](2);
        uint256[] memory c1 = new uint256[](2);
        (c0[0], c0[1]) = (100e18, 200e18);
        (c1[0], c1[1]) = (100e18 + 3600 * 7e17 + 5, 200e18 + 3600 * 3e17 - 5);
        uint256[] memory prior = new uint256[](2);
        (prior[0], prior[1]) = (4e17, 6e17);
        uint256[] memory v = MarketSettlement.voidPrices(c0, c1, 3600, prior);
        assertEq(v[0], 7e17); // floored
        assertEq(v[1], 3e17 - 1);
        v = MarketSettlement.voidPrices(c0, c1, 0, prior);
        assertEq(v[0], 4e17);
        assertEq(v[1], 6e17);
    }

    function testFuzz_voidPrices_sumAtMostOne(uint256 w, uint256 a, uint256 b) public pure {
        w = bound(w, 1, 30 days);
        a = bound(a, 0, 1e18);
        b = bound(b, 0, 1e18 - a);
        uint256[] memory c0 = new uint256[](3);
        uint256[] memory c1 = new uint256[](3);
        (c1[0], c1[1]) = (a * w, b * w);
        c1[2] = w * 1e18 - c1[0] - c1[1]; // the implied last entry, as cumulativeAt builds it
        uint256[] memory v = MarketSettlement.voidPrices(c0, c1, w, new uint256[](3));
        assertLe(v[0] + v[1] + v[2], 1e18);
    }

    function testFuzz_reserveCoversEveryAccount(uint256[4] memory sa, uint256[4] memory sb, uint256[4] memory vr)
        public
        pure
    {
        uint256[] memory a = new uint256[](4);
        uint256[] memory b = new uint256[](4);
        uint256[] memory t = new uint256[](4);
        uint256[] memory v = new uint256[](4);
        uint256 hi;
        for (uint256 i; i < 4; ++i) {
            a[i] = bound(sa[i], 0, 1e15);
            b[i] = bound(sb[i], 0, 1e15);
            t[i] = a[i] + b[i];
            v[i] = bound(vr[i], 0, 25e16); // Σ v ≤ 1e18
            if (t[i] > hi) hi = t[i];
        }
        uint256 reserve = MarketSettlement.voidReserve(t, v);
        assertLe(MarketSettlement.voidOwed(a, v) + MarketSettlement.voidOwed(b, v), reserve);
        assertLe(reserve, hi + 4); // Σ ceil(t_i v_i) ≤ max t · Σ v + n
    }

    function test_setOpenReference_timing() public {
        LMSRMarket u = _fresh();
        u.initialize(
            _config(IMarketFactory.Kind.UPDOWN, _uniform(2), BUDGET),
            address(pool),
            oracle,
            router,
            address(stakingMock)
        );
        vm.prank(oracle);
        vm.expectRevert(ILMSRMarket.TooEarly.selector);
        u.setOpenReference(18_800_000_000, 1e6);
        vm.warp(HALT);
        vm.prank(oracle);
        vm.expectRevert(ILMSRMarket.Halted.selector);
        u.setOpenReference(18_800_000_000, 1e6);
        vm.warp(OPEN);
        vm.prank(oracle);
        u.setOpenReference(18_800_000_000, 1e6);
    }
}
