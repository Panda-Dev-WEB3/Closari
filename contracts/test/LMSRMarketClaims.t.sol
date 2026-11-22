// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../src/LMSRMarket.sol";
import {ILMSRMarket} from "../src/interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "../src/interfaces/IMarketFactory.sol";
import {MockUSDG} from "./mocks/MockUSDG.sol";
import {MarketFixture} from "./utils/MarketFixture.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract LMSRMarketClaimsTest is MarketFixture {
    uint8 internal constant TIE = 3;
    LMSRMarket internal m;

    function setUp() public override {
        super.setUp();
        m = _market(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        _buy(m, alice, 1, 100e6);
        _buy(m, bob, 0, 50e6);
        _buy(m, carol, 1, 30e6);
    }

    function _resolveYes() internal {
        vm.warp(CLOSE);
        vm.prank(oracle);
        m.resolve(1, 18_900_000_000);
    }

    function _void() internal {
        vm.warp(HALT);
        vm.prank(oracle);
        m.voidMarket(TIE);
    }

    function _addrs(address a, address b) internal pure returns (address[] memory x) {
        x = new address[](2);
        (x[0], x[1]) = (a, b);
    }

    function test_claim_beforeFinal_reverts() public {
        vm.expectRevert(ILMSRMarket.NotFinal.selector);
        m.claim(alice);
        assertEq(m.claimable(alice), 0);
    }

    function test_claim_resolved() public {
        _resolveYes();
        assertEq(m.claimable(alice), 100e6);
        uint256 before = usdg.balanceOf(alice);
        vm.expectEmit(true, false, false, true, address(m));
        emit ILMSRMarket.Claimed(alice, 100e6);
        vm.prank(bob); // anyone may call; alice is paid
        assertEq(m.claim(alice), 100e6);
        assertEq(usdg.balanceOf(alice) - before, 100e6);
        assertEq(m.claim(alice), 0); // once
        assertEq(m.claim(bob), 0); // nothing owed, no event
        assertEq(m.claimable(alice), 0);
        assertEq(m.paidOut(), 100e6);
    }

    function test_claim_voided_refundsFees() public {
        uint256 fees = m.feesPaid(alice);
        assertGt(fees, 0);
        _void();
        (,, uint256[] memory v) = m.finalInfo();
        uint256 expected = 100e6 * v[1] / 1e18 + fees;
        uint256 escrow = m.feeEscrow();
        assertEq(m.claimable(alice), expected);
        assertEq(m.claim(alice), expected);
        assertEq(m.feeEscrow(), escrow - fees);
        assertEq(m.paidOut(), expected - fees);
    }

    function test_claimMany_frozenDeferred_othersPaid() public {
        _resolveYes();
        usdg.setFrozen(alice, true);
        vm.expectEmit(true, false, false, true, address(m));
        emit ILMSRMarket.ClaimDeferred(alice, 100e6);
        m.claimMany(_addrs(alice, carol));
        assertEq(m.claimable(alice), 100e6); // still owed
        assertEq(m.claimable(carol), 0);
        assertEq(m.paidOut(), 30e6);
        usdg.setFrozen(alice, false);
        assertEq(m.claim(alice), 100e6);
    }

    function test_claim_pausedToken_deferred_stateUnchanged() public {
        _void();
        uint256 escrow = m.feeEscrow();
        uint256 owed = m.claimable(bob);
        usdg.setPaused(true);
        assertEq(m.claim(bob), 0);
        assertEq(m.feeEscrow(), escrow);
        assertEq(m.paidOut(), 0);
        assertEq(m.claimable(bob), owed);
        usdg.setPaused(false);
        assertEq(m.claim(bob), owed);
    }

    function test_sweep_resolved() public {
        vm.expectRevert(ILMSRMarket.NotFinal.selector);
        m.sweep();
        _resolveYes();
        uint256 cash = m.cash();
        m.sweep();
        (uint256 budget, uint256 returned, uint256 lastWorst, uint256 lastBest) = pool.swept(address(m));
        assertEq(budget, BUDGET);
        assertEq(returned, cash - 130e6); // winning (YES) shares: 100 + 30
        assertEq(lastWorst, cash - 130e6); // max trader liability is YES
        assertEq(lastBest, cash - 50e6); // min is NO
        assertEq(usdg.balanceOf(address(pool)), returned);
        vm.expectRevert(ILMSRMarket.AlreadySwept.selector);
        m.sweep();
        assertEq(m.claim(alice), 100e6); // claims still succeed after the sweep
        assertEq(m.claim(carol), 30e6);
    }

    function test_sweep_voided_thenEveryClaimSucceeds() public {
        _void();
        uint256 reserve = m.liability();
        uint256 cash = m.cash();
        m.sweep();
        (, uint256 returned,,) = pool.swept(address(m));
        assertEq(returned, cash - reserve);
        m.claim(alice);
        m.claim(bob);
        m.claim(carol);
        assertEq(m.feeEscrow(), 0);
        assertLe(m.paidOut(), reserve);
        assertEq(usdg.balanceOf(address(m)), reserve - m.paidOut()); // only rounding dust is left
    }

    function test_sweep_pausedToken_revertsThenSucceeds() public {
        _resolveYes();
        usdg.setPaused(true);
        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        m.sweep();
        assertEq(pool.sweepCalls(), 0);
        usdg.setPaused(false);
        m.sweep();
        assertEq(pool.sweepCalls(), 1);
    }

    function test_pullFees() public {
        uint256 escrow = m.feeEscrow();
        vm.expectRevert(ILMSRMarket.NotRouter.selector);
        m.pullFees();
        vm.prank(router);
        vm.expectRevert(ILMSRMarket.NotResolved.selector);
        m.pullFees();
        _resolveYes();
        vm.prank(router);
        assertEq(m.pullFees(), escrow);
        assertEq(usdg.balanceOf(router), escrow);
        assertEq(m.feeEscrow(), 0);
        vm.prank(router);
        assertEq(m.pullFees(), 0);
        uint256 expectedReturn = m.cash() - 130e6;
        vm.expectEmit(false, false, false, true, address(m));
        emit ILMSRMarket.Swept(expectedReturn, escrow);
        m.sweep();
    }

    function test_pullFees_voided_reverts() public {
        _void();
        vm.prank(router);
        vm.expectRevert(ILMSRMarket.NotResolved.selector);
        m.pullFees();
    }
}
