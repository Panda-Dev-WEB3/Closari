// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../src/LMSRMarket.sol";
import {IMarketFactory} from "../src/interfaces/IMarketFactory.sol";
import {Constants} from "../src/lib/Constants.sol";
import {PriorMath} from "../src/lib/PriorMath.sol";
import {isExpectedTradeRevert} from "./utils/ExpectedReverts.sol";
import {MarketFixture} from "./utils/MarketFixture.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

contract LMSRMarketPropsTest is MarketFixture {
    function _prior(uint256 seed, uint256 n) internal pure returns (uint256[] memory p) {
        p = new uint256[](n);
        uint256 left = 1e18;
        for (uint256 i; i + 1 < n; ++i) {
            p[i] = bound(uint256(keccak256(abi.encode(seed, "p", i))), 0, left);
            left -= p[i];
        }
        p[n - 1] = left;
        p = PriorMath.floorNormalize(p);
    }

    /// Random trades, then every possible winner: the pool loses at most b·ln(1/p_w) ≤ budget (I5), and I1′ holds.
    function testFuzz_worstCaseLoss(uint256 seed, uint8 nRaw, uint8 stepsRaw) public {
        uint256 n = bound(nRaw, 2, 8);
        IMarketFactory.Kind kind = n == 2 ? IMarketFactory.Kind.ABOVE : IMarketFactory.Kind.RANGE;
        uint256[] memory prior = _prior(seed, n);
        LMSRMarket m = _market(kind, prior, BUDGET);
        uint256 b = m.config().bWad / 1e12;
        address[3] memory who = [alice, bob, carol];
        uint256 steps = bound(stepsRaw, 1, 40);
        uint256 successes;
        for (uint256 s; s < steps; ++s) {
            uint256 r = uint256(keccak256(abi.encode(seed, s)));
            address a = who[r % 3];
            uint8 k = uint8((r >> 8) % n);
            uint256 sh = bound(r >> 16, 1, 2 * b);
            if ((r >> 200) % 3 == 0 && m.shares(a, k) > 0) {
                sh = bound(sh, 1, m.shares(a, k));
                vm.prank(a);
                try m.sell(k, sh, 0, type(uint64).max, address(0)) {
                    ++successes;
                } catch (bytes memory err) {
                    assertTrue(isExpectedTradeRevert(err), "unexpected sell revert (panic?)");
                }
            } else {
                vm.prank(a);
                try m.buy(k, sh, type(uint256).max, type(uint64).max, address(0)) {
                    ++successes;
                } catch (bytes memory err) {
                    assertTrue(isExpectedTradeRevert(err), "unexpected buy revert (panic?)");
                }
            }
            vm.warp(block.timestamp + bound(r >> 100, 0, 600));
            if (block.timestamp >= HALT) break;
        }
        emit log_named_uint("successful trades", successes);
        // The first step is always a buy (nobody holds shares yet) of at most 2b from a prior in [0.02, 0.98], which
        // stays inside the price clamp (p <= 0.98e^2/(0.98e^2 + 0.02) ~ 0.9973), so the campaign is never vacuous.
        assertGt(successes, 0, "no trade succeeded");
        uint256 cash = m.cash();
        assertGe(cash, m.liability(), "I1'");
        uint256[] memory p = m.config().priorWad;
        for (uint256 w; w < n; ++w) {
            uint256 tw = m.shares(alice, uint8(w)) + m.shares(bob, uint8(w)) + m.shares(carol, uint8(w));
            int256 result = int256(cash) - int256(tw) - int256(uint256(BUDGET));
            int256 bound_ =
                -int256(FixedPointMathLib.mulDivUp(b, uint256(-FixedPointMathLib.lnWad(int256(p[w]))), 1e18));
            assertGe(result, bound_ - 1, "loss beyond b ln(1/p_w)");
            assertGe(result, -int256(uint256(BUDGET)), "I5");
        }
    }

    function testFuzz_roundTrip_noProfit(uint256 shRaw, uint8 k, bool late) public {
        LMSRMarket m = _market(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        uint256 b = m.config().bWad / 1e12;
        uint256 sh = bound(shRaw, 1, 3 * b);
        k = uint8(bound(k, 0, 1));
        if (late) {
            vm.warp(HALT - 600);
            sh = bound(sh, 1, b / 4); // late-hour cap: <= b/4 shares per outcome
        }
        uint256 paid = _buy(m, alice, k, sh);
        uint256 got = _sell(m, alice, k, sh);
        assertLt(got, paid);
    }

    function testFuzz_roundTrip_noFee_noProfit(uint256 shRaw) public {
        uint256[] memory prior = _uniform(2);
        LMSRMarket m = _market(IMarketFactory.Kind.ABOVE, prior, BUDGET);
        // base 50 bps still applies; also check the gross legs alone favour the market
        uint256 sh = bound(shRaw, 1, 2 * (m.config().bWad / 1e12));
        (uint256 gBuy,) = m.quoteBuy(0, sh, alice);
        _buy(m, alice, 0, sh);
        (uint256 gSell,) = m.quoteSell(0, sh, alice);
        assertLt(gSell, gBuy);
    }

    /// Cumulatives equal a reference integration of the piecewise-constant floored prices.
    function test_twap_checkpoint_exact() public {
        LMSRMarket m = _market(IMarketFactory.Kind.UPDOWN, _uniform(2), BUDGET);
        uint64[6] memory at = [CREATED + 50, OPEN - 3_600, OPEN - 10, OPEN - 1, HALT - 7_200, HALT - 3_600];
        uint256[2] memory ref;
        uint64 last = CREATED;
        uint256[] memory p = m.prices();
        uint256[2] memory refAtOpenCp;
        uint256[2] memory refAtHaltCp;
        for (uint256 i; i < at.length; ++i) {
            vm.warp(at[i]);
            if (at[i] >= OPEN && i > 0 && at[i - 1] < OPEN) {
                vm.prank(oracle);
                m.setOpenReference(18_800_000_000, 0);
            }
            // reference: integrate up to the checkpoint times exactly
            if (last < OPEN - 3_600 && at[i] >= OPEN - 3_600) {
                refAtOpenCp = [ref[0] + p[0] * (OPEN - 3_600 - last), ref[1] + p[1] * (OPEN - 3_600 - last)];
            }
            if (last < HALT - 3_600 && at[i] >= HALT - 3_600) {
                refAtHaltCp = [ref[0] + p[0] * (HALT - 3_600 - last), ref[1] + p[1] * (HALT - 3_600 - last)];
            }
            ref[0] += p[0] * (at[i] - last);
            ref[1] += p[1] * (at[i] - last);
            last = at[i];
            if (at[i] < OPEN) _buy(m, i % 2 == 0 ? alice : bob, uint8(i % 2), 50e6);
            p = m.prices();
        }
        uint256[] memory c = m.cumulativeAt(uint64(block.timestamp));
        assertEq(c[0], ref[0]);
        assertEq(c[0] + c[1], uint256(block.timestamp - CREATED) * 1e18);
        (uint64[2] memory ts, uint256[][2] memory cp) = m.checkpoints();
        assertEq(ts[0], HALT - 3_600);
        assertEq(ts[1], OPEN - 3_600);
        assertEq(cp[1][0], refAtOpenCp[0]);
        assertEq(cp[0][0], refAtHaltCp[0]);
        // no trade after the halt checkpoint in another market: extrapolated exactly
        LMSRMarket q = _market(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        (, uint256[][2] memory cq) = q.checkpoints();
        assertEq(cq[0][0], uint256(HALT - 3_600 - CREATED) * 5e17);
    }
}
