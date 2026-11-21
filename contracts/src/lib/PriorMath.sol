// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Constants} from "./Constants.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/// @notice Seeded opening prices (M2 spec §3). Zero-drift lognormal close-to-close model with daily vol in bps;
///         Φ by Abramowitz & Stegun 26.2.17 (|error| < 7.5e-8). All values WAD.
library PriorMath {
    int256 internal constant WAD = 1e18;
    int256 internal constant P = 231_641_900_000_000_000;
    int256 internal constant B1 = 319_381_530_000_000_000;
    int256 internal constant B2 = -356_563_782_000_000_000;
    int256 internal constant B3 = 1_781_477_937_000_000_000;
    int256 internal constant B4 = -1_821_255_978_000_000_000;
    int256 internal constant B5 = 1_330_274_429_000_000_000;
    int256 internal constant INV_SQRT_2PI = 398_942_280_401_432_678;
    int256 internal constant X_MAX = 9e18;

    /// @dev Standard normal CDF.
    function cdf(int256 x) internal pure returns (uint256) {
        int256 ax = x < 0 ? -x : x;
        if (ax >= X_MAX) return x > 0 ? 1e18 : 0;
        int256 t = (WAD * WAD) / (WAD + (P * ax) / WAD);
        int256 poly = (B4 + (t * B5) / WAD);
        poly = B3 + (t * poly) / WAD;
        poly = B2 + (t * poly) / WAD;
        poly = B1 + (t * poly) / WAD;
        poly = (t * poly) / WAD;
        int256 pdf = (INV_SQRT_2PI * FixedPointMathLib.expWad(-((ax * ax) / WAD) / 2)) / WAD;
        int256 tail = (pdf * poly) / WAD;
        if (tail < 0) tail = 0;
        if (tail > WAD) tail = WAD;
        return uint256(x >= 0 ? WAD - tail : tail);
    }

    /// @dev P(close > k8) = Φ((ln(ref/k) − σ²/2) / σ).
    function probAbove(int256 ref8, int256 k8, uint16 volBps) internal pure returns (uint256) {
        int256 sigma = int256(uint256(volBps)) * 1e14;
        int256 lnRatio = FixedPointMathLib.lnWad((ref8 * WAD) / k8);
        int256 d = ((lnRatio - (sigma * sigma) / WAD / 2) * WAD) / sigma;
        return cdf(d);
    }

    /// @dev Buckets for strictly increasing edges: [P(≤e1), P(e1<·≤e2), …, P(>em)]. One edge gives ABOVE [NO, YES].
    function raw(int256 ref8, int64[] memory edges, uint16 volBps) public pure returns (uint256[] memory p) {
        uint256 m = edges.length;
        p = new uint256[](m + 1);
        uint256 prev = 1e18;
        for (uint256 j; j < m; ++j) {
            uint256 s = probAbove(ref8, edges[j], volBps);
            p[j] = prev > s ? prev - s : 0;
            prev = s < prev ? s : prev;
        }
        p[m] = prev;
    }

    function uniform(uint256 n) internal pure returns (uint256[] memory p) {
        p = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            p[i] = 1e18 / n;
        }
        p[0] += 1e18 - (1e18 / n) * n;
    }

    /// @dev Raises each entry to PRIOR_MIN and moves the difference to the largest entry, so Σ = 1e18 exactly.
    ///      PRIOR_MIN·(n−1) ≤ 0.14 and the largest entry of a distribution over n ≤ 8 buckets with k floored entries
    ///      exceeds (1 − 0.02k)/(n − k), so the largest stays ≥ PRIOR_MIN.
    function floorNormalize(uint256[] memory p) public pure returns (uint256[] memory) {
        uint256 sum;
        uint256 big;
        for (uint256 i; i < p.length; ++i) {
            if (p[i] < Constants.PRIOR_MIN) p[i] = Constants.PRIOR_MIN;
            if (p[i] > p[big]) big = i;
            sum += p[i];
        }
        if (sum > 1e18) p[big] -= sum - 1e18;
        else p[big] += 1e18 - sum;
        return p;
    }

    /// @dev b (base units) with b·ln(1/p_min) ≤ budget, the worst-case loss of a prior-seeded LMSR. 0 outside
    ///      [B_MIN, B_MAX]. A uniform prior gives M1's b·ln n.
    function liquidity(uint96 budget, uint256[] memory prior) public pure returns (uint256 b) {
        uint256 pMin = type(uint256).max;
        for (uint256 i; i < prior.length; ++i) {
            if (prior[i] < pMin) pMin = prior[i];
        }
        uint256 lnInv = uint256(FixedPointMathLib.lnWad(int256(FixedPointMathLib.divWad(1e18, pMin))));
        b = uint256(budget) * 1e18 / (lnInv + 1);
        if (b < Constants.B_MIN || b > Constants.B_MAX) return 0;
    }
}
