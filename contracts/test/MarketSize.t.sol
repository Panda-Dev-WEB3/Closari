// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../src/LMSRMarket.sol";
import {Test} from "forge-std/Test.sol";

/// @notice M3 spec §3: the market keeps about 1 KB under the 24,576-byte limit for M7.
contract MarketSizeTest is Test {
    function test_marketRuntime_underGate() public {
        LMSRMarket impl = new LMSRMarket(address(1), address(2));
        assertLe(address(impl).code.length, 23_500, "LMSRMarket runtime over the M3 size gate");
    }
}
