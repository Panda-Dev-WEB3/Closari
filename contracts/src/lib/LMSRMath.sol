// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/// @notice Fixed-b LMSR from the published formulas (Backend §3.4) on Solady expWad/lnWad. x and b are WAD.
///         Log-sum-exp around m = max x keeps every exp argument ≤ 0. Rounding favours the market.
library LMSRMath {
    int256 internal constant MIN_EXP_ARG = -42e18;

    function cost(uint256[] memory x, uint256 bW) internal pure returns (uint256) {
        uint256 m = _max(x);
        uint256 s;
        for (uint256 i; i < x.length; ++i) {
            int256 a = -int256(FixedPointMathLib.mulDiv(m - x[i], 1e18, bW));
            if (a < MIN_EXP_ARG) continue;
            s += uint256(FixedPointMathLib.expWad(a));
        }
        return m + FixedPointMathLib.mulDiv(bW, uint256(FixedPointMathLib.lnWad(int256(s))), 1e18);
    }

    /// @dev Floored, so Σ ≤ 1e18.
    function prices(uint256[] memory x, uint256 bW) internal pure returns (uint256[] memory p) {
        uint256 m = _max(x);
        uint256 n = x.length;
        p = new uint256[](n);
        uint256 s;
        for (uint256 i; i < n; ++i) {
            int256 a = -int256(FixedPointMathLib.mulDiv(m - x[i], 1e18, bW));
            if (a < MIN_EXP_ARG) continue;
            p[i] = uint256(FixedPointMathLib.expWad(a));
            s += p[i];
        }
        for (uint256 i; i < n; ++i) {
            p[i] = FixedPointMathLib.mulDiv(p[i], 1e18, s);
        }
    }

    /// @dev ceil((C(x + sh·e_k) − C(x)) / 1e12) + 1 base units.
    function buyCost(uint256[] memory x, uint256 bW, uint256 k, uint256 sh) internal pure returns (uint256) {
        uint256 c0 = cost(x, bW);
        uint256[] memory y = _copy(x);
        y[k] += sh * 1e12;
        uint256 c1 = cost(y, bW);
        return (c1 > c0 ? FixedPointMathLib.divUp(c1 - c0, 1e12) : 0) + 1;
    }

    /// @dev max(0, floor((C(x) − C(x − sh·e_k)) / 1e12) − 1) base units.
    function sellProceeds(uint256[] memory x, uint256 bW, uint256 k, uint256 sh) internal pure returns (uint256) {
        uint256 c0 = cost(x, bW);
        uint256[] memory y = _copy(x);
        y[k] -= sh * 1e12;
        uint256 c1 = cost(y, bW);
        uint256 d = c0 > c1 ? (c0 - c1) / 1e12 : 0;
        return d > 0 ? d - 1 : 0;
    }

    function _max(uint256[] memory x) private pure returns (uint256 m) {
        for (uint256 i; i < x.length; ++i) {
            if (x[i] > m) m = x[i];
        }
    }

    function _copy(uint256[] memory x) private pure returns (uint256[] memory y) {
        y = new uint256[](x.length);
        for (uint256 i; i < x.length; ++i) {
            y[i] = x[i];
        }
    }
}
