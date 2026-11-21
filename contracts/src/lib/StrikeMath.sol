// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

/// @notice Deterministic strike and edge generation (Backend §3.3). Mirrored by packages/core/src/strikes/strikes.ts.
library StrikeMath {
    error BadReference();
    error BadTick();
    error BadBps();

    /// @notice roundHalfUp(ref8 × (10_000 + bps) / 10_000, tick8), exact on the rational (no double rounding).
    function strike(int256 ref8, int16 bps, uint32 tick8) internal pure returns (int64) {
        if (ref8 <= 0) revert BadReference();
        if (tick8 == 0) revert BadTick();
        if (bps <= -10_000) revert BadBps();
        int256 tick = int256(uint256(tick8));
        int256 num = ref8 * (10_000 + int256(bps));
        int256 den = 10_000 * tick;
        int256 q = (2 * num + den) / (2 * den);
        return SafeCastLib.toInt64(q * tick);
    }

    /// @notice Strikes by template index; 0 = collapsed (non-positive, or not above the previous kept strike).
    function positional(int256 ref8, int16[] memory bps, uint32 tick8) internal pure returns (int64[] memory out) {
        out = new int64[](bps.length);
        int64 last;
        for (uint256 i; i < bps.length; ++i) {
            int64 s = strike(ref8, bps[i], tick8);
            if (s > last) {
                out[i] = s;
                last = s;
            }
        }
    }

    function compact(int64[] memory p) internal pure returns (int64[] memory edges) {
        uint256 k;
        for (uint256 i; i < p.length; ++i) {
            if (p[i] != 0) ++k;
        }
        edges = new int64[](k);
        k = 0;
        for (uint256 i; i < p.length; ++i) {
            if (p[i] != 0) edges[k++] = p[i];
        }
    }
}
