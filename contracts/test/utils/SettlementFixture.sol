// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../../src/LMSRMarket.sol";
import {SettlementOracle} from "../../src/SettlementOracle.sol";
import {ISettlementOracle} from "../../src/interfaces/ISettlementOracle.sol";
import {MockPythUnique} from "../mocks/MockPythUnique.sol";
import {MockUSDG} from "../mocks/MockUSDG.sol";
import {Fixture} from "./Fixture.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/// @notice The factory with the real LMSRMarket and the real SettlementOracle (Pyth through MockPythUnique).
abstract contract SettlementFixture is Fixture {
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    uint64 internal constant CONF = 9_000_000; // $0.09 on $188.12 (0.048%)
    uint64 internal constant FC = FRI_CLOSE;
    uint64 internal constant FO = FRI_OPEN;

    MockUSDG internal usdg;
    MockPythUnique internal pythU;
    SettlementOracle internal so;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal keeper = makeAddr("keeper");

    function _impl() internal virtual override returns (address) {
        usdg = new MockUSDG();
        return address(new LMSRMarket(address(usdg), PERMIT2));
    }

    function _pythFor() internal virtual override returns (address) {
        pythU = new MockPythUnique(pyth);
        return address(pythU);
    }

    function _deployOracle(address pyth_, address predictedFactory) internal virtual override returns (address) {
        so = new SettlementOracle(pyth_, predictedFactory, address(router), timelock);
        return address(so);
    }

    function setUp() public virtual override {
        super.setUp();
        vm.prank(timelock);
        so.setBounties(2e6, 1e6, 5e5);
        vm.deal(keeper, 1 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
    }

    /// @dev Lists FRI, mints each budget into its market (the M7 pool's job), funds alice and bob.
    function _listAndFund() internal returns (address[] memory markets) {
        markets = _listFri();
        address[2] memory who = [alice, bob];
        for (uint256 j; j < 2; ++j) {
            usdg.mint(who[j], 1_000_000e6);
        }
        for (uint256 i; i < markets.length; ++i) {
            if (markets[i] == address(0)) continue;
            usdg.mint(markets[i], LMSRMarket(markets[i]).config().budget);
            for (uint256 j; j < 2; ++j) {
                vm.prank(who[j]);
                usdg.approve(markets[i], type(uint256).max);
            }
        }
    }

    /// @dev Encodes a MockPyth update locally (same layout as MockPyth.createPriceFeedUpdateData). It must not call
    ///      any contract: tests put vm.expectRevert / vm.expectEmit before helpers that use it, and an external call
    ///      here would become "the next call".
    function _upd(uint64 publishTime, uint64 prev, int64 price, uint64 conf) internal pure returns (bytes[] memory u) {
        PythStructs.PriceFeed memory f;
        f.id = PYTH_ID;
        f.price = PythStructs.Price({price: price, conf: conf, expo: -8, publishTime: publishTime});
        f.emaPrice = f.price;
        u = new bytes[](1);
        u[0] = abi.encode(f, prev);
    }

    /// @dev prev = publishTime − 61 lies before every tier's window, so the update is the first one in it.
    function _submitAs(address who, ISettlementOracle.Tier tier, uint64 pt, int64 price, uint64 conf, uint80 rid)
        internal
    {
        bytes[] memory u = _upd(pt, pt - 61, price, conf);
        vm.prank(who);
        so.submitClose{value: 1}(address(nvda), FRI, tier, u, rid);
    }

    function _submit(ISettlementOracle.Tier tier, uint64 pt, int64 price, uint64 conf, uint80 rid) internal {
        _submitAs(keeper, tier, pt, price, conf, rid);
    }

    /// @dev Phase-1 Chainlink round id for aggregator round `n`.
    function _round(uint64 n, int256 answer, uint256 updatedAt) internal returns (uint80 rid) {
        rid = uint80((uint256(1) << 64) | n);
        feed.setRound(rid, answer, updatedAt);
    }

    /// @dev A fresh Chainlink round that agrees with NVDA_PRICE: the default for tests that do not probe Chainlink.
    function _clOk() internal returns (uint80) {
        return _round(10, NVDA_PRICE, FC - 60);
    }

    function _close() internal view returns (ISettlementOracle.PriceResult memory) {
        return so.closeResult(address(nvda), FRI);
    }

    function _open() internal view returns (ISettlementOracle.PriceResult memory) {
        return so.openResult(address(nvda), FRI);
    }

    function _recordOpenAs(address who, ISettlementOracle.Tier tier, uint64 pt, int64 price, uint64 conf) internal {
        bytes[] memory u = _upd(pt, FO - 1, price, conf);
        vm.prank(who);
        so.recordOpen{value: 1}(address(nvda), FRI, tier, u);
    }
}
