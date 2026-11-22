// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../src/LMSRMarket.sol";
import {ILMSRMarket} from "../src/interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "../src/interfaces/IMarketFactory.sol";
import {MarketSettlement} from "../src/lib/MarketSettlement.sol";
import {MarketFixture} from "./utils/MarketFixture.sol";

/// @notice Backend §3.6 void tests, by name. Fees are on (base 50 bps) and refunded on a void.
contract LMSRMarketVoidPropsTest is MarketFixture {
    uint8 internal constant TIE = 3;
    uint8 internal constant NO_OPEN = 7;
    uint8 internal constant GUARDIAN = 9;
    uint256 internal constant FUNDS = 10_000_000e6;

    function _actors(LMSRMarket m, uint256 k, string memory tag) internal returns (address[] memory a) {
        a = new address[](k);
        for (uint256 i; i < k; ++i) {
            a[i] = makeAddr(string.concat(tag, vm.toString(i)));
            usdg.mint(a[i], FUNDS);
            vm.prank(a[i]);
            usdg.approve(address(m), type(uint256).max);
        }
    }

    function _balances(address[] memory a) internal view returns (uint256 s) {
        for (uint256 i; i < a.length; ++i) {
            s += usdg.balanceOf(a[i]);
        }
    }

    function _claimAll(LMSRMarket m, address[] memory a) internal returns (uint256 paid) {
        for (uint256 i; i < a.length; ++i) {
            paid += m.claim(a[i]);
        }
    }

    function _voidAtHalt(LMSRMarket m) internal {
        vm.warp(HALT);
        vm.prank(oracle);
        m.voidMarket(TIE);
    }

    /// @dev The brief's 4-cycle attack: A buys Δ YES, B buys Δ YES, A sells Δ YES, E buys Δ NO (Δ = b).
    function _washCycle(LMSRMarket m, address[] memory w, uint256 d) internal returns (int256[3] memory net) {
        net[0] += int256(_buy(m, w[0], 1, d));
        net[1] += int256(_buy(m, w[1], 1, d));
        net[0] -= int256(_sell(m, w[0], 1, d));
        net[2] += int256(_buy(m, w[2], 0, d));
    }

    function test_void_washCycle_noDrain() public {
        LMSRMarket m = _market(IMarketFactory.Kind.ABOVE, _uniform(2), 1_000e6);
        address[] memory w = _actors(m, 3, "wash");
        uint256 d = m.config().bWad / 1e12;
        uint256 start = _balances(w);
        for (uint256 c; c < 4; ++c) {
            _washCycle(m, w, d);
        }
        assertEq(m.shares(w[1], 1), 4 * d);
        assertEq(m.shares(w[2], 0), 4 * d);
        _voidAtHalt(m);
        assertLe(m.liability(), m.cash(), "L_void <= cash");
        _claimAll(m, w);
        assertLe(_balances(w), start, "the attackers profit from a void");
        m.sweep();
        (, uint256 returned,,) = pool.swept(address(m));
        assertGe(returned, 1_000e6, "the pool loses on a balanced void");
    }

    function test_void_netPaidRule_isDrainable() public {
        // Reference implementation of the REJECTED rule (refund each account's net USDG paid), test folder only.
        LMSRMarket m = _market(IMarketFactory.Kind.ABOVE, _uniform(2), 1_000e6);
        address[] memory w = _actors(m, 3, "netpaid");
        uint256 d = m.config().bWad / 1e12;
        int256[3] memory net;
        for (uint256 c; c < 4; ++c) {
            int256[3] memory n1 = _washCycle(m, w, d);
            for (uint256 i; i < 3; ++i) {
                net[i] += n1[i];
            }
        }
        uint256 refunds;
        for (uint256 i; i < 3; ++i) {
            if (net[i] > 0) refunds += uint256(net[i]);
        }
        assertGt(refunds, m.cash() + m.feeEscrow(), "the net-paid rule must owe more than the market holds");
    }

    function _randomTrades(LMSRMarket m, address[] memory a, uint256 seed, uint256 count) internal {
        uint8 n = m.config().n;
        for (uint256 k; k < count; ++k) {
            uint256 r = uint256(keccak256(abi.encode(seed, k)));
            uint256 t = block.timestamp + (r % 600);
            vm.warp(t < HALT ? t : HALT - 1);
            address who = a[(r >> 8) % a.length];
            uint8 o = uint8((r >> 16) % n);
            uint256 sh = 1e6 + (r >> 24) % 500e6;
            if ((r >> 64) % 3 != 0) {
                vm.prank(who);
                try m.buy(o, sh, type(uint256).max, type(uint64).max, address(0)) {} catch {}
            } else {
                uint256 held = m.shares(who, o);
                if (held == 0) continue;
                vm.prank(who);
                try m.sell(o, 1 + sh % held, 0, type(uint64).max, address(0)) {} catch {}
            }
        }
    }

    /// forge-config: default.fuzz.runs = 200
    function testFuzz_void_bounded(uint256 seed) public {
        LMSRMarket m = _market(IMarketFactory.Kind.RANGE, _uniform(4), BUDGET);
        address[] memory a = _actors(m, 16, "fz");
        _randomTrades(m, a, seed, 1 + seed % 200);
        _voidAtHalt(m);
        assertLe(m.liability(), m.cash(), "L_void <= cash");
        uint256 bal = usdg.balanceOf(address(m));
        uint256 paid = _claimAll(m, a);
        assertLe(paid, bal);
        assertEq(m.feeEscrow(), 0, "every fee refunded");
        assertLe(m.paidOut(), m.liability());
        m.sweep();
    }

    /// forge-config: default.fuzz.runs = 200
    function testFuzz_void_bounded_arbitrarySimplex(uint256 seed, uint256[3] memory vr) public {
        LMSRMarket m = _market(IMarketFactory.Kind.RANGE, _uniform(4), BUDGET);
        address[] memory a = _actors(m, 16, "sx");
        _randomTrades(m, a, seed, 1 + seed % 200);
        uint256[] memory v = new uint256[](4);
        v[0] = bound(vr[0], 0, 1e18);
        v[1] = bound(vr[1], 0, 1e18 - v[0]);
        v[2] = bound(vr[2], 0, 1e18 - v[0] - v[1]);
        v[3] = 1e18 - v[0] - v[1] - v[2];
        uint256[] memory t = new uint256[](4);
        uint256 owed;
        for (uint256 j; j < a.length; ++j) {
            uint256[] memory sh = new uint256[](4);
            for (uint8 i; i < 4; ++i) {
                sh[i] = m.shares(a[j], i);
                t[i] += sh[i];
            }
            owed += MarketSettlement.voidOwed(sh, v);
        }
        uint256 reserve = MarketSettlement.voidReserve(t, v);
        assertLe(owed, reserve, "per-account floors fit in the reserve");
        assertLe(reserve, m.cash(), "any simplex v: L_void <= cash, so the pool loses at most the budget");
    }

    function test_void_lastMinutePush_unprofitable() public {
        LMSRMarket m = _market(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        uint256 quota = m.config().bWad / 1e12 / 4; // late-hour cap per account and outcome
        address[] memory s = _actors(m, 18, "sybil"); // 18 × b/4 = 4.5 b: YES to about 0.989
        uint256 start = _balances(s);
        vm.warp(HALT - 60);
        for (uint256 i; i < s.length; ++i) {
            _buy(m, s[i], 1, quota);
        }
        assertGt(m.prices()[1], 98e16);
        _voidAtHalt(m);
        (,, uint256[] memory v) = m.finalInfo();
        assertLt(v[1], 52e16, "a 60 s push moves the 60 min TWAP by about 1/60");
        _claimAll(m, s);
        assertLt(_balances(s), start, "the push loses money");
    }

    function test_voidNoOpen_noAtomicPush() public {
        LMSRMarket u = _market(IMarketFactory.Kind.UPDOWN, _uniform(2), BUDGET);
        vm.warp(OPEN - 1800);
        _buy(u, alice, 1, 300e6);
        vm.warp(OPEN + 7_201);
        vm.prank(bob);
        vm.expectRevert(ILMSRMarket.AwaitingOpen.selector); // nobody can push before voidNoOpen
        u.buy(1, 1e6, type(uint256).max, type(uint64).max, address(0));
        (uint64[2] memory ts, uint256[][2] memory cp) = u.checkpoints();
        assertEq(ts[1], OPEN - 3600);
        uint256[] memory c1 = u.cumulativeAt(OPEN);
        vm.prank(oracle);
        u.voidMarket(NO_OPEN);
        (,, uint256[] memory v) = u.finalInfo();
        assertEq(v[1], (c1[1] - cp[1][1]) / 3600, "void price = the 08:30-09:30 TWAP");
    }

    function test_guardianVoid_lifetimeTWAP() public {
        LMSRMarket m = _market(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        uint64 stop = CREATED + 20_000; // before the late hour, so one account can push
        vm.warp(stop - 60);
        _buy(m, bob, 1, m.config().bWad * 45 / 10 / 1e12); // YES to about 0.989
        vm.warp(stop);
        m.voidMarket(GUARDIAN);
        (,, uint256[] memory v) = m.finalInfo();
        assertLe(v[1] - 5e17, uint256(60) * 1e18 / 20_000, "moves v by at most pushDuration / lifetime");
    }
}
