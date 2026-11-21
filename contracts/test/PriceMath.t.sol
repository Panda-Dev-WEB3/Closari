// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {PriceMath} from "../src/lib/PriceMath.sol";
import {Test} from "forge-std/Test.sol";

contract PriceMathHarness {
    function to8(int64 p, uint64 c, int32 e) external pure returns (int256, uint256) {
        return PriceMath.to8(p, c, e);
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
}
