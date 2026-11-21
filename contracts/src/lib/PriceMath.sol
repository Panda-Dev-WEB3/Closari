// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

/// @notice Price unit conversions. This is the ONLY file allowed to do arithmetic with a stock-token multiplier (I11).
///         Pyth prices are share terms and are converted once; Chainlink answers are token terms and never pass here.
library PriceMath {
    error ExpoOutOfRange(int32 expo);
    error ZeroMultiplier();

    /// @notice Pyth (price, conf, expo) → 8 decimals, rounding toward zero.
    function to8(int64 price, uint64 conf, int32 expo) internal pure returns (int256 price8, uint256 conf8) {
        if (expo < -18 || expo > 18) revert ExpoOutOfRange(expo);
        int256 shift = int256(expo) + 8;
        if (shift >= 0) {
            uint256 m = 10 ** uint256(shift);
            price8 = int256(price) * int256(m);
            conf8 = uint256(conf) * m;
        } else {
            uint256 d = 10 ** uint256(-shift);
            price8 = int256(price) / int256(d);
            conf8 = uint256(conf) / d;
        }
    }

    /// @notice Share terms → token terms: price × multiplier / 1e18 (toward zero).
    function toTokenTerms(int256 share8, uint256 multiplierWad) internal pure returns (int256) {
        return share8 * SafeCastLib.toInt256(multiplierWad) / 1e18;
    }

    function toTokenTermsConf(uint256 conf8, uint256 multiplierWad) internal pure returns (uint256) {
        return conf8 * multiplierWad / 1e18;
    }

    /// @notice A token-terms price observed under `multiplierThen`, restated under `multiplierNow`.
    function rescale(int256 price8, uint256 multiplierNow, uint256 multiplierThen) internal pure returns (int256) {
        if (multiplierThen == 0) revert ZeroMultiplier();
        return price8 * SafeCastLib.toInt256(multiplierNow) / SafeCastLib.toInt256(multiplierThen);
    }
}
