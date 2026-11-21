// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMath} from "../src/lib/LMSRMath.sol";
import {Test} from "forge-std/Test.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

contract LMSRMathTest is Test {
    uint256 constant BW = 2_885_390_081e12; // b ≈ 2,885 shares

    function _x(uint256 n) internal pure returns (uint256[] memory) {
        return new uint256[](n);
    }

    function test_cost_uniformIsBLnN() public pure {
        for (uint256 n = 2; n <= 8; ++n) {
            uint256 c = LMSRMath.cost(_x(n), BW);
            uint256 expect = BW * uint256(FixedPointMathLib.lnWad(int256(n * 1e18))) / 1e18;
            assertApproxEqAbs(c, expect, 1e12);
        }
    }

    function test_prices_uniformAndSum() public pure {
        uint256[] memory p = LMSRMath.prices(_x(4), BW);
        uint256 s;
        for (uint256 i; i < 4; ++i) {
            assertApproxEqAbs(p[i], 25e16, 1);
            s += p[i];
        }
        assertLe(s, 1e18);
    }

    function test_buySell_roundingFavoursMarket() public pure {
        uint256[] memory x = _x(2);
        uint256 cost = LMSRMath.buyCost(x, BW, 0, 100e6);
        x[0] = 100e6 * 1e12;
        uint256 back = LMSRMath.sellProceeds(x, BW, 0, 100e6);
        assertGt(cost, back);
        assertGe(cost - back, 2);
        assertLe(cost - back, 3);
    }

    function test_zeroShares_marginsOnly() public pure {
        uint256[] memory x = _x(3);
        assertEq(LMSRMath.buyCost(x, BW, 0, 0), 1);
        x[0] = 5e18;
        assertEq(LMSRMath.sellProceeds(x, BW, 0, 0), 0);
    }

    function test_sellTiny_returnsZero() public pure {
        uint256[] memory x = _x(2);
        x[0] = 1e12;
        assertEq(LMSRMath.sellProceeds(x, BW, 0, 1), 0);
    }

    function test_farBelowMax_termSkipped() public pure {
        uint256[] memory x = _x(3);
        x[0] = 50 * BW; // others are > 42 b below the max
        uint256 c = LMSRMath.cost(x, BW);
        assertApproxEqAbs(c, x[0], 1e12);
        uint256[] memory p = LMSRMath.prices(x, BW);
        assertEq(p[1], 0);
        assertEq(p[2], 0);
        assertEq(p[0], 1e18);
    }

    function test_inputsUnchanged() public pure {
        uint256[] memory x = _x(3);
        x[1] = 7e18;
        LMSRMath.buyCost(x, BW, 1, 5e6);
        LMSRMath.sellProceeds(x, BW, 1, 5e6);
        assertEq(x[1], 7e18);
    }

    function testFuzz_priceSumAtMostOne(uint256 seed, uint8 nRaw) public pure {
        uint256 n = bound(nRaw, 2, 8);
        uint256[] memory x = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            x[i] = bound(uint256(keccak256(abi.encode(seed, i))), 0, 6 * BW);
        }
        uint256[] memory p = LMSRMath.prices(x, BW);
        uint256 s;
        for (uint256 i; i < n; ++i) {
            s += p[i];
        }
        assertLe(s, 1e18);
        assertGe(s, 1e18 - n);
    }
}
