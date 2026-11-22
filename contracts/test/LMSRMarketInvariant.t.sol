// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../src/LMSRMarket.sol";
import {ILMSRMarket} from "../src/interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "../src/interfaces/IMarketFactory.sol";
import {Constants} from "../src/lib/Constants.sol";
import {MockStockToken} from "./mocks/MockStockToken.sol";
import {MockUSDG} from "./mocks/MockUSDG.sol";
import {isExpectedTradeRevert} from "./utils/ExpectedReverts.sol";
import {MarketFixture} from "./utils/MarketFixture.sol";
import {Test} from "forge-std/Test.sol";

contract MarketHandler is Test {
    LMSRMarket public m;
    MockUSDG public usdg;
    MockStockToken public token;
    address[8] internal actors;
    uint64 public halt;
    bool public tradedAtOrAfterHalt;
    bool public unexpectedRevert;
    uint256 public buys;
    uint256 public sells;
    uint256 public calls;
    address public oracle;
    address public factoryAddr;
    bool public claimFailed;

    constructor(LMSRMarket m_, MockUSDG usdg_, MockStockToken token_, uint64 halt_, address oracle_, address factory_) {
        (m, usdg, token, halt, oracle, factoryAddr) = (m_, usdg_, token_, halt_, oracle_, factory_);
        for (uint256 i; i < 8; ++i) {
            actors[i] = address(uint160(0x1000 + i));
            usdg.mint(actors[i], 10_000_000e6);
            vm.prank(actors[i]);
            usdg.approve(address(m), type(uint256).max);
        }
    }

    function buy(uint256 a, uint8 k, uint256 sh) external {
        ++calls;
        address who = actors[a % 8];
        k = uint8(bound(k, 0, m.config().n - 1));
        sh = bound(sh, 1, 2 * (m.config().bWad / 1e12));
        vm.prank(who);
        try m.buy(k, sh, type(uint256).max, type(uint64).max, address(0)) {
            ++buys;
            if (block.timestamp >= halt) tradedAtOrAfterHalt = true;
        } catch (bytes memory err) {
            if (!isExpectedTradeRevert(err)) unexpectedRevert = true;
        }
    }

    function sell(uint256 a, uint8 k, uint256 sh) external {
        ++calls;
        k = uint8(bound(k, 0, m.config().n - 1));
        address who;
        uint256 held;
        for (uint256 j; j < 8 && held == 0; ++j) {
            who = actors[(a % 8 + j) % 8]; // first actor from a with a position in k
            held = m.shares(who, k);
        }
        if (held == 0) return;
        sh = bound(sh, 1, held);
        vm.prank(who);
        try m.sell(k, sh, 0, type(uint64).max, address(0)) {
            ++sells;
            if (block.timestamp >= halt) tradedAtOrAfterHalt = true;
        } catch (bytes memory err) {
            if (!isExpectedTradeRevert(err)) unexpectedRevert = true;
        }
    }

    function warp(uint256 dt) external {
        ++calls;
        vm.warp(block.timestamp + bound(dt, 0, 30 minutes));
    }

    function toggleCA(uint256 r) external {
        ++calls;
        token.setOraclePaused(r % 8 == 0); // paused for ~1 in 8 toggles
    }

    /// @dev Ends the market (guardian void before the halt, resolve after the close, or a settlement void after the
    ///      halt), only once at least one trade happened, so the existing "some trade succeeded" check stays meaningful.
    function end(uint256 r) external {
        ++calls;
        if (m.state() != ILMSRMarket.State.Trading || buys + sells == 0) return;
        uint256 mode = r % 3;
        if (mode == 0 && block.timestamp < halt) {
            vm.prank(factoryAddr);
            m.voidMarket(9);
            return;
        }
        if (mode == 1) {
            uint64 close = m.config().closeTs;
            if (block.timestamp < close) vm.warp(close);
            vm.prank(oracle);
            m.resolve(uint8((r >> 8) % m.config().n), 1);
            return;
        }
        if (block.timestamp < halt) vm.warp(halt);
        vm.prank(oracle);
        m.voidMarket(3);
    }

    function claimAll() external {
        ++calls;
        if (m.state() == ILMSRMarket.State.Trading) return;
        for (uint256 i; i < 8; ++i) {
            try m.claim(actors[i]) {}
            catch {
                claimFailed = true;
            }
        }
    }

    function sweepNow() external {
        ++calls;
        if (m.state() == ILMSRMarket.State.Trading) return;
        try m.sweep() {} catch {} // AlreadySwept on repeats is fine
    }

    function sumShares(uint8 k) external view returns (uint256 s) {
        for (uint256 i; i < 8; ++i) {
            s += m.shares(actors[i], k);
        }
    }
}

contract LMSRMarketInvariantTest is MarketFixture {
    LMSRMarket m;
    MarketHandler h;

    function setUp() public override {
        super.setUp();
        uint256[] memory prior = new uint256[](5);
        (prior[0], prior[1], prior[2], prior[3], prior[4]) = (5e16, 2e17, 5e17, 2e17, 5e16);
        m = _market(IMarketFactory.Kind.RANGE, prior, BUDGET);
        h = new MarketHandler(m, usdg, token, HALT, oracle, address(this));
        targetContract(address(h));
    }

    function invariant_I1prime_cashCoversLiability() public view {
        assertGe(m.cash(), m.liability());
    }

    function invariant_I2_balanceCoversCashAndFees() public view {
        (, uint256 returned,,) = pool.swept(address(m));
        assertGe(usdg.balanceOf(address(m)) + m.paidOut() + returned, m.cash() + m.feeEscrow());
    }

    function invariant_I4_claimsWithinReserve() public view {
        if (m.state() == ILMSRMarket.State.Trading) return;
        assertLe(m.paidOut(), m.liability());
        assertFalse(h.claimFailed(), "a claim reverted");
    }

    function invariant_I16_voidPricesInSimplex() public view {
        if (m.state() != ILMSRMarket.State.Voided) return;
        (,, uint256[] memory v) = m.finalInfo();
        uint256 s;
        for (uint256 i; i < v.length; ++i) {
            s += v[i];
        }
        assertLe(s, 1e18);
    }

    function invariant_I3_pricesInClamp() public view {
        uint256[] memory p = m.prices();
        uint256 s;
        for (uint256 i; i < p.length; ++i) {
            assertGe(p[i], Constants.P_MIN);
            assertLe(p[i], 1e18 - Constants.P_MIN);
            s += p[i];
        }
        assertLe(s, 1e18);
    }

    function invariant_noUnexpectedRevert() public view {
        assertFalse(h.unexpectedRevert(), "panic or unexpected revert in a trade");
    }

    function afterInvariant() public {
        if (vm.envOr("LOG_TRADES", false)) emit log_named_uint("buys", h.buys());
        if (vm.envOr("LOG_TRADES", false)) emit log_named_uint("sells", h.sells());
        if (vm.envOr("LOG_TRADES", false)) emit log_named_uint("calls", h.calls());
        if (h.calls() >= 50) assertGt(h.buys() + h.sells(), 0, "no trade succeeded in a run");
    }

    function invariant_I7_noTradeAfterHalt() public view {
        assertFalse(h.tradedAtOrAfterHalt());
    }

    function invariant_marksMatchPool() public view {
        uint256 hi;
        uint256 lo = type(uint256).max;
        for (uint8 k; k < 5; ++k) {
            uint256 t = h.sumShares(k);
            if (t > hi) hi = t;
            if (t < lo) lo = t;
        }
        if (m.state() == ILMSRMarket.State.Trading) assertEq(hi, m.liability());
        else assertLe(m.liability(), hi); // once final the reserve is the winner's shares or the void floor sum
        assertEq(pool.worst(address(m)), int256(m.cash() - hi));
        assertEq(pool.best(address(m)), int256(m.cash() - lo));
    }
}
