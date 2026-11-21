// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {StrikeMath} from "../src/lib/StrikeMath.sol";
import {Test} from "forge-std/Test.sol";

contract StrikeMathHarness {
    function strike(int256 r, int16 b, uint32 t) external pure returns (int64) {
        return StrikeMath.strike(r, b, t);
    }
}

contract StrikeMathTest is Test {
    uint32 constant TICK = 50_000_000;
    StrikeMathHarness h = new StrikeMathHarness();

    function _launch() internal pure returns (int16[] memory b) {
        b = new int16[](6);
        (b[0], b[1], b[2], b[3], b[4], b[5]) = (-500, -200, -100, 100, 200, 500);
    }

    function test_nvdaExample() public pure {
        int64[] memory s = StrikeMath.positional(18_812_000_000, _launch(), TICK);
        assertEq(s[0], 17_850_000_000);
        assertEq(s[1], 18_450_000_000);
        assertEq(s[2], 18_600_000_000);
        assertEq(s[3], 19_000_000_000);
        assertEq(s[4], 19_200_000_000);
        assertEq(s[5], 19_750_000_000);
    }

    function test_halfUp() public view {
        assertEq(h.strike(10_000_000_000, 25, TICK), 10_050_000_000);
        assertEq(h.strike(10_000_000_000, -25, TICK), 10_000_000_000);
    }

    function test_collapseAndCompact() public pure {
        int64[] memory s = StrikeMath.positional(100_000_000, _launch(), TICK);
        assertEq(s[0], 100_000_000);
        for (uint256 i = 1; i < 6; ++i) {
            assertEq(s[i], 0);
        }
        int64[] memory c = StrikeMath.compact(s);
        assertEq(c.length, 1);
        assertEq(StrikeMath.compact(StrikeMath.positional(10_000_000, _launch(), TICK)).length, 0);
    }

    function test_reverts() public {
        vm.expectRevert(StrikeMath.BadReference.selector);
        h.strike(0, 100, TICK);
        vm.expectRevert(StrikeMath.BadTick.selector);
        h.strike(1, 100, 0);
        vm.expectRevert(StrikeMath.BadBps.selector);
        h.strike(1, -10_000, TICK);
    }

    function test_vectorsMatchTypeScriptReference() public view {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/test/vectors/strikes.json"));
        uint256 count = vm.parseJsonUint(json, ".count");
        assertGt(count, 80);
        for (uint256 i; i < count; ++i) {
            string memory p = string.concat(".cases[", vm.toString(i), "]");
            int256 ref8 = vm.parseJsonInt(json, string.concat(p, ".ref8"));
            uint32 tick8 = uint32(vm.parseJsonUint(json, string.concat(p, ".tick8")));
            int256[] memory bpsRaw = vm.parseJsonIntArray(json, string.concat(p, ".bps"));
            int256[] memory expected = vm.parseJsonIntArray(json, string.concat(p, ".expected"));
            int16[] memory bps = new int16[](bpsRaw.length);
            for (uint256 j; j < bps.length; ++j) {
                bps[j] = int16(bpsRaw[j]);
            }
            int64[] memory got = StrikeMath.positional(ref8, bps, tick8);
            assertEq(got.length, expected.length);
            for (uint256 j; j < got.length; ++j) {
                assertEq(int256(got[j]), expected[j], vm.parseJsonString(json, string.concat(p, ".name")));
            }
        }
    }

    function testFuzz_positional_isOrderedAndWithinHalfTick(int64 ref, uint32 tick) public pure {
        ref = int64(bound(ref, 1e6, 1e13));
        tick = uint32(bound(tick, 1e6, 1e9));
        int16[] memory b = _launch();
        int64[] memory s = StrikeMath.positional(ref, b, tick);
        int64 last;
        for (uint256 i; i < s.length; ++i) {
            if (s[i] == 0) continue;
            assertGt(s[i], last);
            last = s[i];
            // |s × 10_000 − ref × (10_000 + bps)| ≤ tick × 10_000 / 2
            int256 diff = int256(s[i]) * 10_000 - int256(ref) * (10_000 + int256(b[i]));
            if (diff < 0) diff = -diff;
            assertLe(diff, int256(uint256(tick)) * 5_000);
        }
    }
}
