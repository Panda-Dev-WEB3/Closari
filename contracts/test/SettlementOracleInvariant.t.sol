// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../src/LMSRMarket.sol";
import {SettlementOracle} from "../src/SettlementOracle.sol";
import {ILMSRMarket} from "../src/interfaces/ILMSRMarket.sol";
import {ISettlementOracle} from "../src/interfaces/ISettlementOracle.sol";
import {SettlementFixture} from "./utils/SettlementFixture.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {Test} from "forge-std/Test.sol";

/// @notice An adversarial settler: any tier, any price, any time, in any order.
contract OracleHandler is Test {
    SettlementOracle internal so;
    address internal token;
    uint32 internal day;
    uint64 internal close;
    bytes32 internal id;
    uint80 internal rid;
    bool public panicked;
    bool public changed;
    bool internal sawFinal;
    bytes32 internal finalHash;

    constructor(SettlementOracle so_, address token_, uint32 day_, uint64 close_, bytes32 id_, uint80 rid_) {
        (so, token, day, close, id, rid) = (so_, token_, day_, close_, id_, rid_);
    }

    function _upd(uint64 pt, uint64 prev, int64 price, uint64 conf) internal view returns (bytes[] memory u) {
        PythStructs.PriceFeed memory f;
        f.id = id;
        f.price = PythStructs.Price({price: price, conf: conf, expo: -8, publishTime: pt});
        f.emaPrice = f.price;
        u = new bytes[](1);
        u[0] = abi.encode(f, prev);
    }

    function submit(uint8 t, uint256 back, int64 price, uint256 confBps) external {
        ISettlementOracle.Tier tier = ISettlementOracle.Tier(bound(t, 1, 3));
        uint64 w = tier == ISettlementOracle.Tier.A ? 0 : tier == ISettlementOracle.Tier.B ? 5 : 60;
        uint64 pt = close - uint64(bound(back, 0, w));
        price = int64(bound(price, -1e10, 1e12));
        uint64 conf = uint64(bound(confBps, 0, 100) * uint256(price > 0 ? uint64(price) : 1) / 10_000);
        try so.submitClose{value: 1}(token, day, tier, _upd(pt, close - 61, price, conf), rid) {}
        catch (bytes memory e) {
            _check(e);
        }
        _snapshot();
    }

    function finalize() external {
        try so.finalizeClose(token, day) {}
        catch (bytes memory e) {
            _check(e);
        }
        _snapshot();
    }

    function expire() external {
        try so.voidExpired(token, day) {}
        catch (bytes memory e) {
            _check(e);
        }
        _snapshot();
    }

    function settle(uint256 from, uint256 to) external {
        try so.settleMarkets(token, day, bound(from, 0, 8), bound(to, 0, 8)) {}
        catch (bytes memory e) {
            _check(e);
        }
        _snapshot();
    }

    function warp(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 0, 1 hours));
    }

    function _check(bytes memory e) internal {
        bytes4 sel;
        if (e.length >= 4) {
            assembly {
                sel := mload(add(e, 32))
            }
        }
        if (sel == 0x4e487b71) panicked = true; // Panic(uint256)
    }

    function _snapshot() internal {
        ISettlementOracle.PriceResult memory r = so.closeResult(token, day);
        if (!r.final_) return;
        bytes32 h = keccak256(abi.encode(r));
        if (!sawFinal) (sawFinal, finalHash) = (true, h);
        else if (h != finalHash) changed = true;
    }
}

contract SettlementOracleInvariantTest is SettlementFixture {
    OracleHandler internal h;
    address[] internal mk;

    function setUp() public override {
        super.setUp();
        mk = _listAndFund();
        uint80 rid = _round(10, NVDA_PRICE, FC - 60);
        vm.warp(FC - 600);
        h = new OracleHandler(so, address(nvda), FRI, FC, PYTH_ID, rid);
        vm.deal(address(h), 100 ether);
        targetContract(address(h));
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 64
    function invariant_I8_finalNeverChanges() public view {
        assertFalse(h.changed(), "a final close result changed");
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 64
    function invariant_noPanic() public view {
        assertFalse(h.panicked(), "panic in an oracle call");
    }

    /// @dev I14: whatever happened, any caller can make every market final by close + SETTLE + IMPROVE.
    function afterInvariant() public {
        uint64 deadline = FC + so.SETTLE_WINDOW() + so.IMPROVE_WINDOW() + 1;
        if (block.timestamp < deadline) vm.warp(deadline);
        try so.finalizeClose(address(nvda), FRI) {} catch {}
        try so.voidExpired(address(nvda), FRI) {} catch {}
        so.settleMarkets(address(nvda), FRI, 0, mk.length);
        for (uint256 i; i < mk.length; ++i) {
            if (mk[i] != address(0)) {
                assertTrue(LMSRMarket(mk[i]).state() != ILMSRMarket.State.Trading, "a market is still trading");
            }
        }
    }
}
