// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {PriceMath} from "../src/lib/PriceMath.sol";
import {Test} from "forge-std/Test.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

contract PriceMathHarness {
    function to8(int64 p, uint64 c, int32 e) external pure returns (int256, uint256) {
        return PriceMath.to8(p, c, e);
    }

    function toTokenTerms(int256 share8, uint256 multiplierWad) external pure returns (int256) {
        return PriceMath.toTokenTerms(share8, multiplierWad);
    }

    function rescale(int256 price8, uint256 multiplierNow, uint256 multiplierThen) external pure returns (int256) {
        return PriceMath.rescale(price8, multiplierNow, multiplierThen);
    }
}

contract PriceMathTest is Test {
    PriceMathHarness h = new PriceMathHarness();

    function test_to8_identityAtExpoMinus8() public view {
        (int256 p, uint256 c) = h.to8(18_812_000_000, 9_000_000, -8);
        assertEq(p, 18_812_000_000);
        assertEq(c, 9_000_000);
    }

    function test_to8_scalesUpAndDown() public view {
        (int256 p, uint256 c) = h.to8(18_812_000, 9_000, -5);
        assertEq(p, 18_812_000_000);
        assertEq(c, 9_000_000);
        (p, c) = h.to8(1_881_200_000_099, 999, -10);
        assertEq(p, 18_812_000_000); // truncated toward zero
        assertEq(c, 9);
        (p,) = h.to8(-1_881_200_000_099, 0, -10);
        assertEq(p, -18_812_000_000); // toward zero, not floor
    }

    function test_to8_revertsOnExtremeExpo() public {
        vm.expectRevert(abi.encodeWithSelector(PriceMath.ExpoOutOfRange.selector, int32(-19)));
        h.to8(1, 0, -19);
        vm.expectRevert(abi.encodeWithSelector(PriceMath.ExpoOutOfRange.selector, int32(19)));
        h.to8(1, 0, 19);
    }

    function test_toTokenTerms_appliesNvdaMultiplierOnce() public pure {
        assertEq(PriceMath.toTokenTerms(18_812_000_000, 1_000_775_159_164_630_595), 18_826_582_294);
        assertEq(PriceMath.toTokenTermsConf(9_000_000, 3e18), 27_000_000);
    }

    function test_rescale_dividendStepAfterClose() public pure {
        assertEq(PriceMath.rescale(18_812_000_000, 1.01e18, 1e18), 19_000_120_000);
        assertEq(PriceMath.rescale(18_812_000_000, 1e18, 1e18), 18_812_000_000);
    }

    function test_to8_extremeExpoAtInt64Bounds_noOverflow() public view {
        (int256 p, uint256 c) = h.to8(type(int64).max, type(uint64).max, 18);
        assertEq(p, int256(type(int64).max) * 1e26);
        assertEq(c, uint256(type(uint64).max) * 1e26);
        (p,) = h.to8(type(int64).min, 0, 18);
        assertEq(p, int256(type(int64).min) * 1e26);
        (p, c) = h.to8(type(int64).max, type(uint64).max, -18);
        assertEq(p, int256(type(int64).max) / 1e10);
        assertEq(c, uint256(type(uint64).max) / 1e10);
        (p,) = h.to8(type(int64).min, 0, -18);
        assertEq(p, int256(type(int64).min) / 1e10);
    }

    function test_toTokenTerms_revertsOnOversizedMultiplier() public {
        vm.expectRevert(SafeCastLib.Overflow.selector);
        h.toTokenTerms(18_812_000_000, uint256(type(int256).max) + 1);
    }

    function test_rescale_revertsOnOversizedMultiplier() public {
        vm.expectRevert(SafeCastLib.Overflow.selector);
        h.rescale(18_812_000_000, uint256(type(int256).max) + 1, 1e18);
        vm.expectRevert(SafeCastLib.Overflow.selector);
        h.rescale(18_812_000_000, 1e18, uint256(type(int256).max) + 1);
    }

    function test_rescale_revertsOnZeroMultiplierThen() public {
        vm.expectRevert(PriceMath.ZeroMultiplier.selector);
        h.rescale(18_812_000_000, 1e18, 0);
    }
}
