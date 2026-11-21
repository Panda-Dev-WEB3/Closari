// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @notice Constants shared by the factory, the market and (M3) the oracle: one definition each (M1 obligation 5).
library Constants {
    uint64 internal constant HALT_BEFORE_CLOSE = 600;
    uint64 internal constant CA_AFTER = 3_600;
    uint64 internal constant VOID_TWAP_WINDOW = 3_600;
    uint64 internal constant RAMP_WINDOW = 1_800;
    uint64 internal constant LATE_HOUR = 3_600;
    uint256 internal constant P_MIN = 1e15; // price clamp, WAD
    uint256 internal constant PRIOR_MIN = 2e16; // opening-price floor, WAD
    uint16 internal constant MAX_BASE_FEE_BPS = 200;
    uint16 internal constant MAX_RAMP_BPS = 500;
    uint16 internal constant MAX_DISCOUNT_BPS = 3_000;
    uint16 internal constant MIN_VOL_BPS = 25;
    uint16 internal constant MAX_VOL_BPS = 2_000;
    uint256 internal constant B_MIN = 1e8; // 100 shares, base units
    uint256 internal constant B_MAX = 1e12; // 1e6 shares, base units
}
