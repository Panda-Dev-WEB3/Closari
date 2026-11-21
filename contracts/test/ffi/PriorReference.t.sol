// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {PriorMath} from "../../src/lib/PriorMath.sol";
import {Test} from "forge-std/Test.sol";

contract PriorReferenceTest is Test {
    function testFuzz_raw_vs_reference(int256 refRaw, uint16 volRaw, uint256 seed, uint8 mRaw) public {
        int256 ref8 = bound(refRaw, 1e8, 5_000e8); // $1 .. $5,000
        uint16 vol = uint16(bound(volRaw, 25, 2_000));
        uint256 m = bound(mRaw, 1, 7);
        int64[] memory e = new int64[](m);
        int256 lo = ref8 * 80 / 100;
        for (uint256 i; i < m; ++i) {
            lo += int256(bound(uint256(keccak256(abi.encode(seed, i))), 1e6, uint256(ref8 / 20)));
            e[i] = int64(lo);
        }
        uint256[] memory sol = PriorMath.raw(ref8, e, vol);
        string[] memory cmd = new string[](6 + m);
        (cmd[0], cmd[1], cmd[2], cmd[3]) = ("bun", "run", "../packages/core/scripts/lmsr-ffi.ts", "prior");
        (cmd[4], cmd[5]) = (vm.toString(ref8), vm.toString(uint256(vol)));
        for (uint256 i; i < m; ++i) {
            cmd[6 + i] = vm.toString(int256(e[i]));
        }
        uint256[] memory ref = abi.decode(vm.ffi(cmd), (uint256[]));
        assertEq(sol.length, ref.length);
        for (uint256 i; i < sol.length; ++i) {
            assertApproxEqAbs(sol[i], ref[i], 2e11, "bucket off by more than 2e-7");
        }
    }
}
