// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ILMSRMarket} from "../src/interfaces/ILMSRMarket.sol";
import {PriorMath} from "../src/lib/PriorMath.sol";
import {MockMarket} from "./mocks/MockMarket.sol";
import {Fixture} from "./utils/Fixture.sol";

contract MarketFactoryPriorTest is Fixture {
    function test_listing_seedsPriorAndLiquidity() public {
        address[] memory m = _listFri();
        for (uint256 i; i < m.length; ++i) {
            if (m[i] == address(0)) continue;
            ILMSRMarket.Config memory c = MockMarket(m[i]).config();
            uint256[] memory expect =
                i == 7 ? PriorMath.uniform(2) : PriorMath.floorNormalize(PriorMath.raw(NVDA_PRICE, c.edges, 300));
            for (uint256 j; j < c.n; ++j) {
                assertEq(c.priorWad[j], expect[j]);
            }
            assertEq(c.bWad, PriorMath.liquidity(c.budget, expect) * 1e12);
        }
    }

    function test_abovePrior_isMonotoneInStrike() public {
        address[] memory m = _listFri();
        uint256 prevYes = 1e18;
        for (uint256 i; i < 6; ++i) {
            uint256 yes = MockMarket(m[i]).config().priorWad[1];
            assertLe(yes, prevYes); // higher strike → lower chance of closing above
            prevYes = yes;
        }
    }

    function test_farStrikeLists_atLaunchBudget() public {
        address[] memory m = _listFri();
        assertTrue(m[0] != address(0)); // −5%
        assertTrue(m[5] != address(0)); // +5%
    }
}
