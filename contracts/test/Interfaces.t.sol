// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IExchangeCalendar} from "../src/interfaces/IExchangeCalendar.sol";
import {IFeeRouter} from "../src/interfaces/IFeeRouter.sol";
import {IHousePool} from "../src/interfaces/IHousePool.sol";
import {ILMSRMarket} from "../src/interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "../src/interfaces/IMarketFactory.sol";
import {ISettlementOracle} from "../src/interfaces/ISettlementOracle.sol";
import {IStockTokenAllowList} from "../src/interfaces/IStockTokenAllowList.sol";
import {Test} from "forge-std/Test.sol";

contract InterfacesTest is Test {
    function test_selectorsMatchBrief() public pure {
        assertEq(IMarketFactory.setFees.selector, bytes4(keccak256("setFees(uint16,uint16)")));
        assertEq(ISettlementOracle.finalizeOpen.selector, bytes4(keccak256("finalizeOpen(address,uint32)")));
        assertEq(ISettlementOracle.setBounties.selector, bytes4(keccak256("setBounties(uint96,uint96,uint96)")));
        assertEq(ISettlementOracle.bounties.selector, bytes4(keccak256("bounties()")));
        assertEq(ILMSRMarket.claimable.selector, bytes4(keccak256("claimable(address)")));
        assertEq(ILMSRMarket.finalInfo.selector, bytes4(keccak256("finalInfo()")));
        assertEq(IMarketFactory.listDay.selector, bytes4(keccak256("listDay(address,uint32,bytes[])")));
        assertEq(IExchangeCalendar.setSessions.selector, bytes4(keccak256("setSessions(uint32[],(uint64,uint64)[])")));
        assertEq(
            IStockTokenAllowList.setAsset.selector,
            bytes4(keccak256("setAsset(address,(bytes32,address,uint32,uint96,uint96,uint96,uint16,bool))"))
        );
        assertEq(
            ISettlementOracle.submitClose.selector,
            bytes4(keccak256("submitClose(address,uint32,uint8,bytes[],uint80)"))
        );
        assertEq(IHousePool.allocate.selector, bytes4(keccak256("allocate(address,uint256)")));
        assertEq(IFeeRouter.creditBounty.selector, bytes4(keccak256("creditBounty(address,uint256)")));
        assertEq(IFeeRouter.fundBounty.selector, bytes4(keccak256("fundBounty(uint256)")));
        assertEq(ILMSRMarket.pullFees.selector, bytes4(keccak256("pullFees()")));
        assertEq(
            ILMSRMarket.initialize.selector,
            bytes4(
                keccak256(
                    "initialize((address,uint32,uint8,uint8,int64[],uint64,uint64,uint64,uint64,uint256,uint256,uint96,uint256[],uint16,uint16),address,address,address,address)"
                )
            )
        );
    }
}
