// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../src/LMSRMarket.sol";
import {ILMSRMarket} from "../src/interfaces/ILMSRMarket.sol";
import {ISettlementOracle} from "../src/interfaces/ISettlementOracle.sol";
import {SettlementFixture} from "./utils/SettlementFixture.sol";

/// @notice One day end to end with the real factory, markets and oracle; then the next day lists from the oracle's
///         close with no Pyth update (M1 obligation 1).
contract SettlementE2ETest is SettlementFixture {
    function test_listTradeOpenCloseSettleClaimSweep_thenNextDayLists() public {
        address[] memory mk = _listAndFund();
        LMSRMarket above = LMSRMarket(mk[3]); // +100 bps strike
        vm.prank(alice);
        above.buy(1, 50e6, type(uint256).max, type(uint64).max, address(0));
        vm.prank(bob);
        above.buy(0, 20e6, type(uint256).max, type(uint64).max, address(0));

        vm.warp(FO + 2);
        _recordOpenAs(keeper, ISettlementOracle.Tier.A, FO, NVDA_PRICE, CONF);
        LMSRMarket ud = LMSRMarket(mk[7]);
        vm.prank(alice);
        ud.buy(1, 10e6, type(uint256).max, type(uint64).max, address(0));

        int64 s = above.config().edges[0] + 100_000_000; // $1 above the strike, clear of every tie zone
        uint80 rid = _round(10, s, FC - 60);
        vm.warp(FC + 5);
        _submit(ISettlementOracle.Tier.A, FC, s, CONF, rid);
        so.settleMarkets(address(nvda), FRI, 0, mk.length);

        uint256 swept;
        for (uint256 i; i < mk.length; ++i) {
            if (mk[i] == address(0)) continue;
            assertTrue(LMSRMarket(mk[i]).state() != ILMSRMarket.State.Trading);
            LMSRMarket(mk[i]).sweep();
            ++swept;
        }
        assertEq(pool.sweepCalls(), swept);
        assertEq(above.claim(alice), 50e6);
        assertEq(above.claim(bob), 0);
        assertEq(ud.claim(alice), 10e6);

        vm.warp(MON_OPEN - 3 hours);
        vm.prank(lister);
        factory.listDay(address(nvda), MON, new bytes[](0));
        assertEq(factory.dayInfo(address(nvda), MON).refPrice8, s);
    }
}
