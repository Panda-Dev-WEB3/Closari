// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Constants} from "../src/lib/Constants.sol";
import {PriorMath} from "../src/lib/PriorMath.sol";
import {Test} from "forge-std/Test.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

contract PriorMathHarness {
    function cdf(int256 x) external pure returns (uint256) {
        return PriorMath.cdf(x);
    }

    function raw(int256 ref8, int64[] memory e, uint16 v) external pure returns (uint256[] memory) {
        return PriorMath.raw(ref8, e, v);
    }

    function floorNormalize(uint256[] memory p) external pure returns (uint256[] memory) {
        return PriorMath.floorNormalize(p);
    }

    function liquidity(uint96 budget, uint256[] memory p) external pure returns (uint256) {
        return PriorMath.liquidity(budget, p);
    }

    function uniform(uint256 n) external pure returns (uint256[] memory) {
        return PriorMath.uniform(n);
    }
}

contract PriorMathTest is Test {
    PriorMathHarness h = new PriorMathHarness();
    int256 constant REF = 18_812_000_000;

    function test_cdf_knownValues() public view {
        assertApproxEqAbs(h.cdf(0), 5e17, 1e9); // A&S polynomial at t=1 sums to 1 - 1.05e-9, so cdf(0) = 0.5 + 5.2e-10
        assertApproxEqAbs(h.cdf(1.96e18), 975_002_104_851_779_520, 1e11); // A&S 26.2.17: |err| < 7.5e-8
        assertApproxEqAbs(h.cdf(-1.96e18), 24_997_895_148_220_480, 1e11);
        assertEq(h.cdf(9e18), 1e18);
        assertEq(h.cdf(-9e18), 0);
    }

    function testFuzz_cdf_monotoneAndBounded(int256 a, int256 b) public view {
        a = bound(a, -10e18, 10e18);
        b = bound(b, -10e18, 10e18);
        if (a > b) (a, b) = (b, a);
        uint256 ca = h.cdf(a);
        uint256 cb = h.cdf(b);
        assertLe(ca, 1e18);
        assertLe(ca, cb + 1e11); // monotone up to the approximation error
    }

    function test_raw_abovePlus5_at3pct_isAbout5pct() public view {
        int64[] memory e = new int64[](1);
        e[0] = int64(REF * 105 / 100);
        uint256[] memory p = h.raw(REF, e, 300);
        assertEq(p.length, 2);
        assertEq(p[0] + p[1], 1e18);
        assertGt(p[1], 0.049e18);
        assertLt(p[1], 0.052e18);
    }

    function test_floorNormalize_sumsExactlyAndRespectsFloor() public view {
        uint256[] memory p = new uint256[](5);
        (p[0], p[1], p[2], p[3], p[4]) = (1e15, 3e17, 6e17, 99e15 - 2, 1e15);
        uint256[] memory q = h.floorNormalize(p);
        uint256 sum;
        for (uint256 i; i < 5; ++i) {
            assertGe(q[i], Constants.PRIOR_MIN);
            sum += q[i];
        }
        assertEq(sum, 1e18);
        assertEq(q[0], Constants.PRIOR_MIN);
        assertEq(q[1], 3e17); // only the largest absorbs the difference
    }

    function testFuzz_floorNormalize(uint256 seed, uint8 nRaw) public view {
        uint256 n = bound(nRaw, 2, 8);
        uint256[] memory p = new uint256[](n);
        uint256 left = 1e18;
        for (uint256 i; i + 1 < n; ++i) {
            p[i] = bound(uint256(keccak256(abi.encode(seed, i))), 0, left);
            left -= p[i];
        }
        p[n - 1] = left;
        uint256[] memory q = h.floorNormalize(p);
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            assertGe(q[i], Constants.PRIOR_MIN);
            sum += q[i];
        }
        assertEq(sum, 1e18);
    }

    function test_liquidity_uniformMatchesLnN() public view {
        uint256 b = h.liquidity(2_000e6, h.uniform(2));
        assertApproxEqAbs(b, 2_885_390_081, 1); // M1's b for n = 2
        assertLe(b * 693_147_180_559_945_310 / 1e18, 2_000e6);
    }

    function testFuzz_liquidity_lossBound(uint96 budget, uint256 pMinRaw) public view {
        budget = uint96(bound(budget, 10e6, 1_000_000e6));
        uint256 pMin = bound(pMinRaw, Constants.PRIOR_MIN, 5e17);
        uint256[] memory p = new uint256[](2);
        (p[0], p[1]) = (pMin, 1e18 - pMin);
        uint256 b = h.liquidity(budget, p);
        if (b == 0) return; // outside [B_MIN, B_MAX]
        // b · ln(1/pMin) ≤ budget
        uint256 lnInv = uint256(-FixedPointMathLib.lnWad(int256(pMin)));
        assertLe(b * lnInv / 1e18, budget);
    }

    function test_liquidity_rangeBounds() public view {
        uint256[] memory p = h.uniform(2);
        assertEq(h.liquidity(50e6, p), 0); // ≈72 shares < B_MIN
        assertGt(h.liquidity(100e6, p), 0); // ≈144 shares
        assertEq(h.liquidity(800_000e6, p), 0); // > B_MAX
    }
}
