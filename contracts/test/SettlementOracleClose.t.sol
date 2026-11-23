// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ISettlementOracle} from "../src/interfaces/ISettlementOracle.sol";
import {SettlementFixture} from "./utils/SettlementFixture.sol";
import {PythErrors} from "@pythnetwork/pyth-sdk-solidity/PythErrors.sol";

contract SettlementOracleCloseTest is SettlementFixture {
    ISettlementOracle.Tier internal constant A = ISettlementOracle.Tier.A;
    ISettlementOracle.Tier internal constant B = ISettlementOracle.Tier.B;
    ISettlementOracle.Tier internal constant C = ISettlementOracle.Tier.C;
    int64 internal constant P = NVDA_PRICE;

    function _void() internal view returns (ISettlementOracle.VoidReason) {
        return _close().dayVoid;
    }

    // ------------------------------------------------------------ bounties

    function test_setBounties() public {
        vm.expectRevert(ISettlementOracle.NotTimelock.selector);
        so.setBounties(1, 1, 1);
        vm.prank(timelock);
        vm.expectRevert(ISettlementOracle.BountyTooHigh.selector);
        so.setBounties(5e6 + 1, 0, 0);
        vm.expectEmit(false, false, false, true, address(so));
        emit ISettlementOracle.BountiesSet(3e6, 2e6, 1e6);
        vm.prank(timelock);
        so.setBounties(3e6, 2e6, 1e6);
        (uint96 c, uint96 b, uint96 o) = so.bounties();
        assertEq(c, 3e6);
        assertEq(b, 2e6);
        assertEq(o, 1e6);
    }

    // ------------------------------------------------------------ timing and tiers

    function test_submit_notListed_and_tooEarly() public {
        bytes[] memory u = _upd(MON_CLOSE, MON_CLOSE - 61, P, CONF);
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(ISettlementOracle.NotListed.selector, address(nvda), MON));
        so.submitClose{value: 1}(address(nvda), MON, A, u, 0);
        _listAndFund();
        uint80 rid = _clOk();
        vm.warp(FC - 1);
        u = _upd(FC, FC - 61, P, CONF);
        vm.prank(keeper);
        vm.expectRevert(ISettlementOracle.TooEarly.selector);
        so.submitClose{value: 1}(address(nvda), FRI, A, u, rid);
    }

    function test_tierA_finalAtOnce_bountyAndRefund() public {
        _listAndFund();
        uint80 rid = _clOk();
        vm.warp(FC + 5);
        bytes[] memory u = _upd(FC, FC - 61, P, CONF);
        uint256 before = keeper.balance;
        vm.expectEmit(true, true, false, true, address(so));
        emit ISettlementOracle.DayFinal(address(nvda), FRI, P, ISettlementOracle.VoidReason.NONE);
        vm.prank(keeper);
        so.submitClose{value: 0.5 ether}(address(nvda), FRI, A, u, rid);
        assertEq(keeper.balance, before - 1, "only the 1 wei Pyth fee is kept");
        ISettlementOracle.PriceResult memory r = _close();
        assertTrue(r.final_);
        assertEq(r.price8, P);
        assertEq(r.conf8, CONF);
        assertEq(uint8(r.tier), uint8(A));
        assertEq(router.bounties(keeper), 2e6);
        vm.expectRevert(ISettlementOracle.AlreadyFinal.selector);
        _submit(A, FC, P, CONF, rid);
    }

    function test_insufficientFee() public {
        _listAndFund();
        uint80 rid = _clOk();
        vm.warp(FC + 5);
        bytes[] memory u = _upd(FC, FC - 61, P, CONF);
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(ISettlementOracle.InsufficientFee.selector, 1));
        so.submitClose(address(nvda), FRI, A, u, rid);
    }

    function test_tierPrecedence_improveWindowFromFirstSubmission() public {
        _listAndFund();
        uint80 rid = _clOk();
        vm.warp(FC + 10);
        _submitAs(keeper, C, FC - 30, P, CONF, rid);
        assertFalse(_close().final_);
        assertEq(_close().firstSubmitTs, FC + 10);
        vm.expectRevert(ISettlementOracle.TierNotHigher.selector);
        _submitAs(keeper, C, FC - 30, P, CONF, rid);
        vm.warp(FC + 100);
        _submitAs(bob, B, FC - 2, P + 1, CONF, rid);
        assertEq(_close().firstSubmitTs, FC + 10, "the window never extends");
        vm.warp(FC + 10 + 1799);
        vm.expectRevert(ISettlementOracle.TooEarly.selector);
        so.finalizeClose(address(nvda), FRI);
        vm.warp(FC + 10 + 1800);
        vm.expectRevert(ISettlementOracle.TooLate.selector);
        _submitAs(keeper, A, FC, P, CONF, rid);
        so.finalizeClose(address(nvda), FRI);
        ISettlementOracle.PriceResult memory r = _close();
        assertTrue(r.final_);
        assertEq(r.price8, P + 1);
        assertEq(router.bounties(bob), 2e6, "the bounty goes to the submitter of the final result");
        assertEq(router.bounties(keeper), 0);
        vm.expectRevert(ISettlementOracle.AlreadyFinal.selector);
        so.finalizeClose(address(nvda), FRI);
    }

    function test_tierA_replacesB() public {
        _listAndFund();
        uint80 rid = _clOk();
        vm.warp(FC + 10);
        _submit(B, FC - 2, P + 7, CONF, rid);
        _submit(A, FC, P, CONF, rid);
        assertTrue(_close().final_);
        assertEq(_close().price8, P);
    }

    function test_tooLate_and_voidExpired() public {
        _listAndFund();
        uint80 rid = _clOk();
        uint256 credits = router.creditCalls();
        vm.warp(FC + 7_200);
        vm.expectRevert(ISettlementOracle.TooEarly.selector);
        so.voidExpired(address(nvda), FRI);
        vm.warp(FC + 7_201);
        vm.expectRevert(ISettlementOracle.TooLate.selector);
        _submit(A, FC, P, CONF, rid);
        so.voidExpired(address(nvda), FRI);
        assertTrue(_close().final_);
        assertEq(uint8(_void()), uint8(ISettlementOracle.VoidReason.NO_PRICE));
        assertEq(router.creditCalls(), credits, "voidExpired pays no bounty");
        vm.expectRevert(ISettlementOracle.AlreadyFinal.selector);
        so.voidExpired(address(nvda), FRI);
    }

    function test_voidExpired_refusedOnceSomethingIsStored() public {
        _listAndFund();
        uint80 rid = _clOk();
        vm.warp(FC + 7_000);
        _submit(C, FC - 30, P, CONF, rid);
        vm.warp(FC + 7_201);
        vm.expectRevert(ISettlementOracle.TooEarly.selector);
        so.voidExpired(address(nvda), FRI);
    }

    // ------------------------------------------------------------ binding (I17)

    function test_binding_wrongSecond() public {
        _listAndFund();
        uint80 rid = _clOk();
        vm.warp(FC + 5);
        vm.expectRevert(PythErrors.PriceFeedNotFoundWithinRange.selector);
        _submit(A, FC - 1, P, CONF, rid); // tier A accepts only the bell second
    }

    function test_binding_notFirstUpdateInWindow() public {
        _listAndFund();
        uint80 rid = _clOk();
        vm.warp(FC + 5);
        bytes[] memory u = _upd(FC - 2, FC - 3, P, CONF); // an earlier update exists inside the B window
        vm.prank(keeper);
        vm.expectRevert(PythErrors.PriceFeedNotFoundWithinRange.selector);
        so.submitClose{value: 1}(address(nvda), FRI, B, u, rid);
    }

    function test_binding_usesListingSnapshot() public {
        _listAndFund();
        _setNvda(keccak256("test:other-feed"), true, BUDGET); // the live allow-list changes after listing
        uint80 rid = _clOk();
        vm.warp(FC + 5);
        _submit(A, FC, P, CONF, rid); // still bound to the snapshotted PYTH_ID
        assertTrue(_close().final_);
    }

    // ------------------------------------------------------------ per-submission voids

    function test_badPrice() public {
        _listAndFund();
        uint80 rid = _clOk();
        vm.warp(FC + 5);
        _submit(A, FC, 0, 0, rid);
        assertEq(uint8(_void()), uint8(ISettlementOracle.VoidReason.BAD_PRICE));
    }

    function test_confWide_clearedByHigherTier() public {
        _listAndFund();
        uint80 rid = _clOk();
        vm.warp(FC + 5);
        _submit(C, FC - 30, P, uint64(uint256(int256(P)) / 100), rid); // 1% > 0.5%
        assertEq(uint8(_void()), uint8(ISettlementOracle.VoidReason.CONF_WIDE));
        _submit(B, FC - 2, P, CONF, rid);
        assertEq(uint8(_void()), uint8(ISettlementOracle.VoidReason.NONE));
    }

    // ------------------------------------------------------------ Chainlink

    function test_cl_freshAgree_freshDiverge_stale() public {
        _listAndFund();
        uint80 rid = _round(10, P * 1005 / 1000, FC - 60); // 0.5%: agrees
        vm.warp(FC + 5);
        vm.expectEmit(true, true, false, true, address(so));
        emit ISettlementOracle.CrossCheck(address(nvda), FRI, rid, P * 1005 / 1000, FC - 60, true, 50);
        _submit(C, FC - 30, P, CONF, rid);
        assertEq(uint8(_void()), uint8(ISettlementOracle.VoidReason.NONE));
        // later tiers are checked against the SAME stored round: a 2% Pyth move now diverges
        _submit(B, FC - 2, P * 102 / 100, CONF, 0);
        assertEq(uint8(_void()), uint8(ISettlementOracle.VoidReason.DIVERGENCE));
    }

    function test_cl_freshDiverges() public {
        _listAndFund();
        uint80 rid = _round(10, P * 102 / 100, FC - 900); // fresh at exactly CL_FRESH
        vm.warp(FC + 5);
        _submit(A, FC, P, CONF, rid);
        assertEq(uint8(_void()), uint8(ISettlementOracle.VoidReason.DIVERGENCE));
    }

    function test_cl_staleRound_pythGoverns() public {
        _listAndFund();
        uint80 rid = _round(10, P * 15 / 10, FC - 901);
        vm.warp(FC + 5);
        _submit(A, FC, P, CONF, rid);
        assertEq(uint8(_void()), uint8(ISettlementOracle.VoidReason.NONE));
    }

    function test_cl_oldPhaseRejected() public {
        _listAndFund();
        uint80 old = _round(10, P, FC - 60);
        feed.setRound(uint80((uint256(2) << 64) | 1), P, FC + 100); // phase 2 starts after the bell
        vm.warp(FC + 200);
        vm.expectRevert(ISettlementOracle.PhaseMismatch.selector);
        _submit(A, FC, P, CONF, old);
        _submit(A, FC, P, CONF, 0); // no phase-2 round at or before the bell: cross-check unavailable
        assertTrue(_close().final_);
    }

    function test_cl_zeroRoundRefusedWhenARoundExists() public {
        _listAndFund();
        _round(1, P, FC - 3_000);
        _round(2, P, FC - 60);
        vm.warp(FC + 5);
        vm.expectRevert(ISettlementOracle.BadRound.selector);
        _submit(A, FC, P, CONF, 0);
    }

    function test_cl_mustBeTheLastRoundAtOrBeforeTheBell() public {
        _listAndFund();
        uint80 r10 = _round(10, P, FC - 120);
        uint80 r11 = _round(11, P, FC - 60);
        uint80 r12 = _round(12, P, FC + 5);
        vm.warp(FC + 10);
        vm.expectRevert(ISettlementOracle.BadRound.selector);
        _submit(A, FC, P, CONF, r10); // r11 is also before the bell
        vm.expectRevert(ISettlementOracle.BadRound.selector);
        _submit(A, FC, P, CONF, r12); // after the bell
        _submit(A, FC, P, CONF, r11);
        assertTrue(_close().final_);
    }

    function test_cl_nextRoundReverts_isAbsent() public {
        _listAndFund();
        uint80 rid = _clOk();
        feed.setRevertOnMissing(true);
        vm.warp(FC + 5);
        _submit(A, FC, P, CONF, rid);
        assertTrue(_close().final_);
    }

    // ------------------------------------------------------------ corporate actions (frozen at the first submission)

    function test_ca_multiplierChanged() public {
        _listAndFund();
        uint80 rid = _clOk();
        nvda.setMultiplier(2e18);
        vm.warp(FC + 5);
        _submit(A, FC, P, CONF, rid);
        assertEq(uint8(_void()), uint8(ISettlementOracle.VoidReason.CORP_ACTION));
    }

    function test_ca_scheduledInsideAndOutsideWindow() public {
        _listAndFund();
        uint80 rid = _clOk();
        nvda.schedule(2e18, FC + 3_601); // outside [createdTs, closeTs + CA_AFTER]
        vm.warp(FC + 5);
        _submit(C, FC - 30, P, CONF, rid);
        assertEq(uint8(_void()), uint8(ISettlementOracle.VoidReason.NONE));
    }

    function test_ca_scheduledInsideWindow() public {
        _listAndFund();
        uint80 rid = _clOk();
        nvda.schedule(2e18, FC + 3_600);
        vm.warp(FC + 5);
        _submit(A, FC, P, CONF, rid);
        assertEq(uint8(_void()), uint8(ISettlementOracle.VoidReason.CORP_ACTION));
    }

    function test_ca_frozenAtFirstSubmission() public {
        _listAndFund();
        uint80 rid = _clOk();
        vm.warp(FC + 5);
        _submit(C, FC - 30, P, CONF, rid);
        nvda.setOraclePaused(true); // after the first submission: ignored
        _submit(B, FC - 2, P, CONF, rid);
        assertEq(uint8(_void()), uint8(ISettlementOracle.VoidReason.NONE));
    }

    function test_pause_atFirstSubmission_cannotBeCleared() public {
        _listAndFund();
        uint80 rid = _clOk();
        nvda.setOraclePaused(true);
        vm.warp(FC + 5);
        _submit(C, FC - 30, P, CONF, rid);
        assertEq(uint8(_void()), uint8(ISettlementOracle.VoidReason.ORACLE_PAUSED));
        nvda.setOraclePaused(false);
        _submit(A, FC, P, CONF, rid);
        assertEq(uint8(_void()), uint8(ISettlementOracle.VoidReason.ORACLE_PAUSED));
    }

    // ------------------------------------------------------------ units (I11)

    function test_multiplier_appliedOnce_chainlinkNever() public {
        nvda.setMultiplier(2e18); // before listing: the snapshot is 2e18
        _listAndFund();
        uint80 rid = _round(10, 2 * P, FC - 60); // Chainlink is already token terms
        vm.warp(FC + 5);
        _submit(A, FC, P, CONF, rid); // Pyth is share terms
        ISettlementOracle.PriceResult memory r = _close();
        assertEq(r.price8, 2 * P);
        assertEq(r.conf8, 2 * CONF);
        assertEq(uint8(r.dayVoid), uint8(ISettlementOracle.VoidReason.NONE));
    }
}
