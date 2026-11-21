// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMath} from "../../src/lib/LMSRMath.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Differential fuzz vs the 60-digit reference (Backend §9). Runs only under FOUNDRY_PROFILE=ffi.
contract LMSRReferenceTest is Test {
    function _ref(string memory side, uint256 bW, uint256 k, uint256 sh, uint256[] memory x)
        internal
        returns (uint256)
    {
        string[] memory cmd = new string[](8 + x.length);
        (cmd[0], cmd[1], cmd[2]) = ("bun", "run", "../packages/core/scripts/lmsr-ffi.ts");
        (cmd[3], cmd[4], cmd[5]) = ("cost", side, vm.toString(bW));
        (cmd[6], cmd[7]) = (vm.toString(k), vm.toString(sh));
        for (uint256 i; i < x.length; ++i) {
            cmd[8 + i] = vm.toString(x[i]);
        }
        return abi.decode(vm.ffi(cmd), (uint256));
    }

    function testFuzz_cost_vs_reference(uint256 seed, uint8 nRaw, uint256 bRaw, uint256 shRaw, uint8 kRaw) public {
        uint256 n = bound(nRaw, 2, 8);
        uint256 bW = bound(bRaw, 100e6, 1e12) * 1e12; // b in [100, 1e6] shares
        uint256 k = bound(kRaw, 0, n - 1);
        uint256[] memory x = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            // states within the clamp: |x_i − x_j| ≤ ~6.9 b
            x[i] = bound(uint256(keccak256(abi.encode(seed, i))), 0, 6 * bW) / 1e12 * 1e12;
        }
        uint256 sh = bound(shRaw, 1, 2 * bW / 1e12);

        uint256 solBuy = LMSRMath.buyCost(x, bW, k, sh);
        uint256 refBuy = _ref("buy", bW, k, sh, x); // ceil(exact)
        assertGe(solBuy, refBuy, "buy below reference");
        assertLe(solBuy, refBuy + 2, "buy above reference + 2");

        if (x[k] >= sh * 1e12) {
            uint256 solSell = LMSRMath.sellProceeds(x, bW, k, sh);
            uint256 refSell = _ref("sell", bW, k, sh, x); // floor(exact)
            assertLe(solSell, refSell, "sell above reference");
            assertGe(solSell + 2, refSell, "sell below reference - 2");
        }
    }
}
