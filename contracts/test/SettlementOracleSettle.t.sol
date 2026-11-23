// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../src/LMSRMarket.sol";
import {ILMSRMarket} from "../src/interfaces/ILMSRMarket.sol";
import {ISettlementOracle} from "../src/interfaces/ISettlementOracle.sol";
import {SettlementFixture} from "./utils/SettlementFixture.sol";

contract SettlementOracleSettleTest is SettlementFixture {
    ISettlementOracle.Tier internal constant A = ISettlementOracle.Tier.A;
    ISettlementOracle.Tier internal constant B = ISettlementOracle.Tier.B;
    ISettlementOracle.Tier internal constant C = ISettlementOracle.Tier.C;
    int64 internal constant P = NVDA_PRICE;
    uint8 internal constant TIE = 3;
    uint8 internal constant NO_OPEN = 7;

    address[] internal mk;

    function _m(uint256 i) internal view returns (LMSRMarket) {
        return LMSRMarket(mk[i]);
    }

    function _reason(uint256 i) internal view returns (uint8 r) {
        (, r,) = _m(i).finalInfo();
    }

    function _winner(uint256 i) internal view returns (uint8 w) {
        (w,,) = _m(i).finalInfo();
    }

    function _openA(int64 o, uint64 conf) internal {
        vm.warp(FO + 2);
        _recordOpenAs(keeper, A, FO, o, conf);
    }

    function _closeA(int64 s, uint64 conf) internal {
        uint80 rid = _round(10, s, FC - 60);
        vm.warp(FC + 5);
        _submit(A, FC, s, conf, rid);
    }

    function _settleAll() internal {
        so.settleMarkets(address(nvda), FRI, 0, type(uint256).max);
    }

    // ------------------------------------------------------------ settleMarkets

    function test_settle_requiresFinalClose() public {
        mk = _listAndFund();
        vm.expectRevert(ISettlementOracle.NotFinal.selector);
        _settleAll();
    }

    function test_settle_aboveTieZoneBoundary() public {
        mk = _listAndFund();
        int64 k = _m(0).config().edges[0];
        _openA(P, CONF);
        _closeA(k + int64(CONF), CONF); // |S − K| = c: inside the tie zone
        _settleAll();
        assertEq(uint8(_m(0).state()), uint8(ILMSRMarket.State.Voided));
        assertEq(_reason(0), TIE);
    }

    function test_settle_aboveJustOutsideTieZone() public {
        mk = _listAndFund();
        int64 k = _m(0).config().edges[0];
        _openA(P, CONF);
        _closeA(k + int64(CONF) + 1, CONF);
        _settleAll();
        assertEq(uint8(_m(0).state()), uint8(ILMSRMarket.State.Resolved));
        assertEq(_winner(0), 1);
    }

    function test_settle_aboveBelowStrike() public {
        mk = _listAndFund();
        int64 k = _m(5).config().edges[0]; // +500 bps strike
        _openA(P, CONF);
        _closeA(k - int64(CONF) - 1, CONF);
        _settleAll();
        assertEq(_winner(5), 0);
    }

    function test_settle_rangeBucketAndTie() public {
        mk = _listAndFund();
        int64[] memory e = _m(6).config().edges;
        assertEq(e.length, 4);
        _openA(P, CONF);
        _closeA(e[2] + int64(CONF) + 1, CONF); // above E_0, E_1, E_2 and outside every tie zone
        _settleAll();
        assertEq(_winner(6), 3);
    }

    function test_settle_rangeTie() public {
        mk = _listAndFund();
        int64[] memory e = _m(6).config().edges;
        _openA(P, CONF);
        _closeA(e[1] - int64(CONF), CONF);
        _settleAll();
        assertEq(_reason(6), TIE);
    }

    function test_settle_upDown_tieUpDown() public {
        mk = _listAndFund();
        _openA(P, CONF);
        _closeA(P + 2 * int64(CONF), CONF); // |S − O| = c + c_o
        _settleAll();
        assertEq(_reason(7), TIE);
    }

    function test_settle_upDown_up() public {
        mk = _listAndFund();
        _openA(P, CONF);
        _closeA(P + 2 * int64(CONF) + 1, CONF);
        _settleAll();
        assertEq(_winner(7), 1);
    }

    function test_settle_upDown_down() public {
        mk = _listAndFund();
        _openA(P, CONF);
        _closeA(P - 2 * int64(CONF) - 1, CONF);
        _settleAll();
        assertEq(uint8(_m(7).state()), uint8(ILMSRMarket.State.Resolved));
        assertEq(_winner(7), 0);
    }

    function test_settle_upDown_noOpen() public {
        mk = _listAndFund();
        _closeA(P, CONF);
        vm.expectEmit(true, true, false, true, address(so));
        emit ISettlementOracle.OpenFinal(address(nvda), FRI, 0, ISettlementOracle.VoidReason.NO_OPEN);
        _settleAll();
        assertEq(_reason(7), NO_OPEN);
        assertTrue(_open().final_);
    }

    function test_settle_dayVoidVoidsEveryMarket() public {
        mk = _listAndFund();
        _openA(P, CONF);
        nvda.setOraclePaused(true);
        _closeA(P, CONF);
        _settleAll();
        for (uint256 i; i < mk.length; ++i) {
            assertEq(_reason(i), uint8(ISettlementOracle.VoidReason.ORACLE_PAUSED));
        }
    }

    function test_settle_whileUsdgPaused_claimsWait() public {
        mk = _listAndFund();
        vm.prank(alice);
        _m(0).buy(1, 10e6, type(uint256).max, type(uint64).max, address(0)); // YES on the −500 bps strike
        _openA(P, CONF);
        _closeA(P, CONF);
        usdg.setPaused(true);
        _settleAll(); // settlement moves no tokens, so a USDG pause cannot block it
        for (uint256 i; i < mk.length; ++i) {
            if (mk[i] != address(0)) assertTrue(_m(i).state() != ILMSRMarket.State.Trading);
        }
        assertEq(_m(0).claim(alice), 0, "deferred while USDG is paused");
        usdg.setPaused(false);
        assertEq(_m(0).claim(alice), 10e6);
    }

    function test_settle_skipsEmptyAndFinal_batchBountyOnce() public {
        pool.setRefuseMarket(factory.predictMarket(address(nvda), FRI, 2), true);
        mk = _listAndFund();
        assertEq(mk[2], address(0));
        vm.prank(guardian);
        factory.guardianVoid(mk[1], keccak256("closure")); // real market: voided now, GUARDIAN
        assertEq(_reason(1), uint8(ISettlementOracle.VoidReason.GUARDIAN));
        _openA(P, CONF);
        _closeA(P, CONF);
        vm.prank(alice);
        so.settleMarkets(address(nvda), FRI, 0, 3); // settles 0, skips the voided 1 and the empty 2
        assertEq(router.bounties(alice), 1e6);
        vm.prank(bob);
        so.settleMarkets(address(nvda), FRI, 3, 100); // `to` is clamped
        assertEq(router.bounties(bob), 0, "one batch bounty per token-day");
        for (uint256 i; i < mk.length; ++i) {
            if (mk[i] != address(0)) assertTrue(_m(i).state() != ILMSRMarket.State.Trading);
        }
        assertEq(_reason(1), uint8(ISettlementOracle.VoidReason.GUARDIAN), "a final market is never touched");
    }

    // ------------------------------------------------------------ opens

    function test_recordOpen_tierA_pushes_tradingResumes() public {
        mk = _listAndFund();
        LMSRMarket u = _m(7);
        vm.warp(FO + 1);
        vm.prank(alice);
        vm.expectRevert(ILMSRMarket.AwaitingOpen.selector);
        u.buy(1, 1e6, type(uint256).max, type(uint64).max, address(0));
        vm.warp(FO + 2);
        bytes[] memory upd = _upd(FO, FO - 1, P, CONF);
        vm.expectEmit(true, true, false, true, address(so));
        emit ISettlementOracle.OpenFinal(address(nvda), FRI, P, ISettlementOracle.VoidReason.NONE);
        vm.prank(keeper);
        so.recordOpen{value: 1}(address(nvda), FRI, A, upd);
        assertEq(u.config().edges[0], P);
        assertEq(router.bounties(keeper), 5e5);
        vm.prank(alice);
        u.buy(1, 1e6, type(uint256).max, type(uint64).max, address(0));
    }

    function test_recordOpen_tierC_thenFinalizeOpen() public {
        mk = _listAndFund();
        vm.warp(FO + 40);
        _recordOpenAs(bob, C, FO + 30, P, CONF);
        assertEq(_m(7).config().edges.length, 0, "not passed to the market before final");
        vm.warp(FO + 40 + 1799);
        vm.expectRevert(ISettlementOracle.TooEarly.selector);
        so.finalizeOpen(address(nvda), FRI);
        vm.warp(FO + 40 + 1800);
        so.finalizeOpen(address(nvda), FRI);
        assertEq(_m(7).config().edges[0], P);
        assertEq(router.bounties(bob), 5e5);
        vm.expectRevert(ISettlementOracle.AlreadyFinal.selector);
        so.finalizeOpen(address(nvda), FRI);
    }

    function test_recordOpen_wideConfReverts_higherTierStillLands() public {
        mk = _listAndFund();
        vm.warp(FO + 10);
        vm.expectRevert(ISettlementOracle.BadOpen.selector);
        _recordOpenAs(keeper, A, FO, P, uint64(uint256(int256(P)) / 100));
        _recordOpenAs(keeper, B, FO + 2, P, CONF);
        assertEq(uint8(_open().tier), uint8(B));
    }

    function test_recordOpen_tooEarly() public {
        mk = _listAndFund();
        vm.warp(FO - 1);
        vm.expectRevert(ISettlementOracle.TooEarly.selector);
        _recordOpenAs(keeper, A, FO, P, CONF);
    }

    function test_recordOpen_noUpDownMarket() public {
        (int16[] memory s, int16[] memory e,) = factory.template();
        vm.prank(timelock);
        factory.setTemplate(s, e, false);
        mk = _listAndFund();
        vm.warp(FO + 2);
        vm.expectRevert(ISettlementOracle.NoUpDownMarket.selector);
        _recordOpenAs(keeper, A, FO, P, CONF);
    }

    function test_voidNoOpen() public {
        mk = _listAndFund();
        vm.warp(FO + 7_200);
        vm.expectRevert(ISettlementOracle.TooEarly.selector);
        so.voidNoOpen(address(nvda), FRI);
        vm.warp(FO + 7_201);
        so.voidNoOpen(address(nvda), FRI);
        assertEq(_reason(7), NO_OPEN);
        vm.expectRevert(ISettlementOracle.AlreadyFinal.selector);
        so.voidNoOpen(address(nvda), FRI);
        vm.expectRevert(ISettlementOracle.AlreadyFinal.selector);
        _recordOpenAs(keeper, C, FO + 30, P, CONF);
    }

    function test_missedFinalizeOpen_settlementUsesTheOraclesOpen() public {
        mk = _listAndFund();
        vm.warp(FO + 40);
        _recordOpenAs(keeper, C, FO + 30, P, CONF); // nobody calls finalizeOpen
        _closeA(P + 2 * int64(CONF) + 1, CONF);
        _settleAll();
        assertTrue(_open().final_);
        assertEq(_m(7).config().edges.length, 0, "never passed to the market after the halt");
        assertEq(_winner(7), 1);
    }
}
