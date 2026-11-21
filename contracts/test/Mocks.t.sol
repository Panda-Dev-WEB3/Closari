// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {MockHousePool} from "./mocks/MockHousePool.sol";
import {MockStockToken, MockStockTokenLookalike} from "./mocks/MockStockToken.sol";
import {MockUSDG} from "./mocks/MockUSDG.sol";
import {Test} from "forge-std/Test.sol";

contract MocksTest is Test {
    function test_stockTokens_shareCodehash_lookalikeDiffers() public {
        MockStockToken a = new MockStockToken(1e18);
        MockStockToken b = new MockStockToken(3e18);
        MockStockTokenLookalike c = new MockStockTokenLookalike(1e18);
        assertEq(address(a).codehash, address(b).codehash);
        assertTrue(address(a).codehash != address(c).codehash);
    }

    function test_pool_refusesSelectedCall() public {
        MockHousePool p = new MockHousePool();
        p.setRefuseCall(1, true);
        p.allocate(address(1), 10);
        vm.expectRevert(MockHousePool.Refused.selector);
        p.allocate(address(2), 10);
        // A refused call reverts its own allocateCalls++, so the next call reuses index 1. Clear the refusal first.
        p.setRefuseCall(1, false);
        p.allocate(address(3), 10);
        assertEq(p.allocated(address(1)), 10);
        assertEq(p.allocated(address(2)), 0);
        assertEq(p.allocated(address(3)), 10);
    }

    function test_usdg_freezeAndPause() public {
        MockUSDG u = new MockUSDG();
        u.mint(address(this), 100e6);
        u.setFrozen(address(0xBEEF), true);
        vm.expectRevert(abi.encodeWithSelector(MockUSDG.Frozen.selector, address(0xBEEF)));
        u.transfer(address(0xBEEF), 1);
        u.setPaused(true);
        vm.expectRevert(MockUSDG.Paused.selector);
        u.transfer(address(0xCAFE), 1);
    }
}
