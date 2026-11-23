// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ISettlementOracle} from "../../src/interfaces/ISettlementOracle.sol";
import {IStockToken} from "../../src/interfaces/external/IStockToken.sol";
import {SettlementOracleHarness} from "../harness/SettlementOracleHarness.sol";
import {AggregatorV3Interface} from "@chainlink/AggregatorV3Interface.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {Test, console2} from "forge-std/Test.sol";

/// @notice Chain 4663. Chainlink round location runs whenever RPC_4663 is set. The Pyth tests need a real
///         Hermes update in env vars (a Hermes key is required to fetch one; never commit it) and skip otherwise.
///         They are a release gate before M8 (M3 spec §14).
contract OracleForkTest is Test {
    address internal constant PYTH_4663 = 0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a;
    uint64 internal constant CLOSE_20261117 = 1_794_949_200; // Tue 2026-11-17 16:00 ET (21:00 UTC)

    bool internal enabled;
    string internal cfg;
    SettlementOracleHarness internal h;

    function setUp() public {
        string memory rpc = vm.envOr("RPC_4663", string(""));
        enabled = bytes(rpc).length != 0;
        if (!enabled) return;
        vm.createSelectFork(rpc);
        cfg = vm.readFile(string.concat(vm.projectRoot(), "/config/assets.4663.json"));
        h = new SettlementOracleHarness(PYTH_4663);
    }

    modifier onlyFork() {
        if (!enabled) vm.skip(true);
        _;
    }

    /// @dev Binary search inside the current phase for the last round with updatedAt ≤ ts; 0 if the phase starts later.
    function _lastRoundAtOrBefore(AggregatorV3Interface agg, uint64 ts) internal view returns (uint80) {
        (uint80 latest,,,,) = agg.latestRoundData();
        uint256 phase = latest >> 64;
        (,,, uint256 first,) = agg.getRoundData(uint80((phase << 64) | 1));
        if (first > ts) return 0;
        uint256 lo = 1;
        uint256 hi = uint64(latest);
        while (lo < hi) {
            uint256 mid = (lo + hi + 1) / 2;
            (,,, uint256 u,) = agg.getRoundData(uint80((phase << 64) | mid));
            if (u != 0 && u <= ts) lo = mid;
            else hi = mid - 1;
        }
        return uint80((phase << 64) | lo);
    }

    function _checkRound(string memory ticker) internal {
        address feed = vm.parseJsonAddress(cfg, string.concat(".assets.", ticker, ".clFeed"));
        AggregatorV3Interface agg = AggregatorV3Interface(feed);
        uint80 rid = _lastRoundAtOrBefore(agg, CLOSE_20261117);
        if (rid == 0) {
            (bool none,,,,) = h.locate(feed, 0, CLOSE_20261117);
            assertFalse(none, "no round in this phase before the bell: cross-check unavailable");
            return;
        }
        (bool ok, bool fresh, int256 answer, uint256 updatedAt, uint80 used) = h.locate(feed, rid, CLOSE_20261117);
        console2.log(ticker, uint256(answer), updatedAt, fresh);
        assertTrue(ok);
        assertEq(used, rid);
        assertLe(updatedAt, CLOSE_20261117);
        if (uint64(rid) > 1) {
            vm.expectRevert(ISettlementOracle.BadRound.selector);
            h.locate(feed, rid - 1, CLOSE_20261117); // an older round cannot be chosen
        }
        vm.expectRevert(ISettlementOracle.BadRound.selector);
        h.locate(feed, 0, CLOSE_20261117); // "no round" cannot be claimed when one exists
        if ((rid >> 64) > 1) {
            vm.expectRevert(ISettlementOracle.PhaseMismatch.selector);
            h.locate(feed, uint80((uint256((rid >> 64) - 1) << 64) | 1), CLOSE_20261117);
        }
    }

    function test_chainlinkRound_SPY_20261117() public onlyFork {
        _checkRound("SPY");
    }

    function test_chainlinkRound_NVDA_20261117() public onlyFork {
        _checkRound("NVDA");
    }

    /// @dev PYTH_FIXTURE_NVDA = hex update bytes for the NVDA regular-session feed at PYTH_FIXTURE_CLOSE_TS, tier
    ///      PYTH_FIXTURE_TIER (3 = A, 2 = B, 1 = C). Confirms parsePriceFeedUpdatesUnique semantics on the deployed
    ///      Pyth (Backend §3.5 (U)).
    function test_pythUnique_realFixture() public onlyFork {
        string memory hexUpd = vm.envOr("PYTH_FIXTURE_NVDA", string(""));
        if (bytes(hexUpd).length == 0) {
            console2.log("skipped: PYTH_FIXTURE_NVDA not set (needs a Hermes key)");
            vm.skip(true);
        }
        bytes[] memory u = new bytes[](1);
        u[0] = vm.parseBytes(hexUpd);
        uint64 closeTs = uint64(vm.envUint("PYTH_FIXTURE_CLOSE_TS"));
        uint256 tier = vm.envUint("PYTH_FIXTURE_TIER");
        uint64 w = tier == 3 ? 0 : tier == 2 ? 5 : 60;
        bytes32 id = vm.parseJsonBytes32(cfg, ".assets.NVDA.pythId");
        uint256 fee = IPyth(PYTH_4663).getUpdateFee(u);
        (int64 p,, uint64 pt,) = h.parseUnique{value: fee}(id, 1e18, closeTs - w, closeTs, u);
        assertGt(p, 0);
        assertGe(pt, closeTs - w);
        assertLe(pt, closeTs);
        vm.expectRevert(); // the same update is not the first one in a window that starts after it
        h.parseUnique{value: fee}(id, 1e18, pt + 1, pt + 61, u);
    }

    /// @dev I11 release gate: SOXX (multiplier ≈ 3.00135e18). Applied once, Pyth × multiplier matches Chainlink
    ///      within 1%; not applied it is about 3× off. Env: SOXX_TOKEN, SOXX_CL_FEED, SOXX_PYTH_ID,
    ///      PYTH_FIXTURE_SOXX (update at the bell), PYTH_FIXTURE_SOXX_CLOSE_TS.
    function test_soxx_multiplierAppliedOnce() public onlyFork {
        string memory hexUpd = vm.envOr("PYTH_FIXTURE_SOXX", string(""));
        if (bytes(hexUpd).length == 0) {
            console2.log("skipped: PYTH_FIXTURE_SOXX not set (needs a Hermes key)");
            vm.skip(true);
        }
        bytes[] memory u = new bytes[](1);
        u[0] = vm.parseBytes(hexUpd);
        uint64 closeTs = uint64(vm.envUint("PYTH_FIXTURE_SOXX_CLOSE_TS"));
        address feed = vm.envAddress("SOXX_CL_FEED");
        uint256 snap = IStockToken(vm.envAddress("SOXX_TOKEN")).uiMultiplier();
        uint256 fee = IPyth(PYTH_4663).getUpdateFee(u);
        (int64 p,,,) = h.parseUnique{value: fee}(vm.envBytes32("SOXX_PYTH_ID"), snap, closeTs, closeTs, u);
        uint80 rid = _lastRoundAtOrBefore(AggregatorV3Interface(feed), closeTs);
        (,, int256 cl,,) = h.locate(feed, rid, closeTs);
        uint256 diff = cl > p ? uint256(cl - p) : uint256(p - cl);
        assertLe(diff * 10_000, uint256(cl) * 100, "Pyth x multiplier must match Chainlink within 1%");
    }
}
