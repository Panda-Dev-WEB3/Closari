// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../src/LMSRMarket.sol";
import {ILMSRMarket} from "../src/interfaces/ILMSRMarket.sol";
import {MockUSDG} from "./mocks/MockUSDG.sol";
import {Fixture} from "./utils/Fixture.sol";

/// @notice The factory with the real LMSRMarket implementation (M1 obligation: the mock market is replaced in M2).
contract MarketFactoryLMSRTest is Fixture {
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    MockUSDG internal usdgMock;
    address internal alice = makeAddr("alice");

    function _impl() internal override returns (address) {
        usdgMock = new MockUSDG();
        return address(new LMSRMarket(address(usdgMock), PERMIT2));
    }

    /// @dev pool.allocate moves no USDG in M2: stand in for the M7 pool by minting each budget into its market.
    function _fund(address[] memory markets) internal {
        for (uint256 i; i < markets.length; ++i) {
            if (markets[i] != address(0)) usdgMock.mint(markets[i], LMSRMarket(markets[i]).config().budget);
        }
    }

    function test_listDay_wiresRealMarkets() public {
        address[] memory markets = _listFri();
        assertEq(markets.length, 8);
        for (uint256 i; i < markets.length; ++i) {
            LMSRMarket m = LMSRMarket(markets[i]);
            assertTrue(factory.isMarket(address(m)));
            assertEq(m.factory(), address(factory));
            assertEq(uint8(m.state()), uint8(ILMSRMarket.State.Trading));
            assertEq(m.cash(), m.config().budget);
            uint256[] memory p = m.prices();
            uint256[] memory prior = m.config().priorWad;
            assertEq(p.length, prior.length);
            for (uint256 k; k < p.length; ++k) {
                assertApproxEqAbs(p[k], prior[k], 1e6);
            }
        }
    }

    function test_realMarket_tradesAndMarksThePool() public {
        address[] memory markets = _listFri();
        _fund(markets);
        LMSRMarket m = LMSRMarket(markets[0]);
        usdgMock.mint(alice, 1_000e6);
        vm.startPrank(alice);
        usdgMock.approve(address(m), type(uint256).max);
        uint256 paid = m.buy(1, 10e6, type(uint256).max, type(uint64).max, address(0));
        uint256 got = m.sell(1, 5e6, 0, type(uint64).max, address(0));
        vm.stopPrank();
        assertEq(m.shares(alice, 1), 5e6);
        assertEq(usdgMock.balanceOf(alice), 1_000e6 - paid + got);
        assertGt(pool.markCalls(), 0);
        assertEq(pool.worst(address(m)), int256(m.cash() - m.liability()));
    }

    function test_listDay_gas_realMarket() public {
        uint256 g = gasleft();
        _listFri();
        g -= gasleft();
        emit log_named_uint("listDay gas (real LMSRMarket)", g);
        assertLt(g, 8_000_000);
    }
}
