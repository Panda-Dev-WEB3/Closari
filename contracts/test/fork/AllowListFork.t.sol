// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {StockTokenAllowList} from "../../src/StockTokenAllowList.sol";
import {IStockTokenAllowList} from "../../src/interfaces/IStockTokenAllowList.sol";
import {IStockToken} from "../../src/interfaces/external/IStockToken.sol";
import {AggregatorV3Interface} from "@chainlink/AggregatorV3Interface.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Runs against chain 4663: `RPC_4663` (archive RPC for a pinned `FORK_BLOCK`; else `latest`).
contract AllowListForkTest is Test {
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    string internal deployments;
    string internal config;
    StockTokenAllowList internal list;
    bool internal enabled;

    function setUp() public {
        string memory rpc = vm.envOr("RPC_4663", string(""));
        enabled = bytes(rpc).length != 0;
        if (!enabled) return;
        uint256 blk = vm.envOr("FORK_BLOCK", uint256(0));
        if (blk == 0) vm.createSelectFork(rpc);
        else vm.createSelectFork(rpc, blk);
        deployments = vm.readFile(string.concat(vm.projectRoot(), "/deployments/4663-assets.json"));
        config = vm.readFile(string.concat(vm.projectRoot(), "/config/assets.4663.json"));
        list = new StockTokenAllowList(
            vm.parseJsonAddress(deployments, ".beacon"),
            vm.parseJsonBytes32(deployments, ".proxyCodehash"),
            address(this)
        );
    }

    modifier onlyFork() {
        if (!enabled) vm.skip(true);
        _;
    }

    function _token(string memory t) internal view returns (address) {
        return vm.parseJsonAddress(deployments, string.concat(".tokens.", t));
    }

    function test_launchTokensAndSoxxAreGenuine() public onlyFork {
        string[] memory tickers = vm.parseJsonStringArray(config, ".tickers");
        for (uint256 i; i < tickers.length; ++i) {
            assertTrue(list.isGenuine(_token(tickers[i])), tickers[i]);
        }
        assertTrue(list.isGenuine(_token("SOXX")), "SOXX");
    }

    function test_lookalikesRejected() public onlyFork {
        assertFalse(list.isGenuine(USDG));
        // Same 283-byte proxy, different embedded beacon: the exact look-alike attack.
        bytes memory code = _token("NVDA").code;
        bytes20 beacon = bytes20(vm.parseJsonAddress(deployments, ".beacon"));
        bytes20 other = bytes20(address(0xBADBEAC0));
        uint256 replaced;
        for (uint256 i; i + 20 <= code.length; ++i) {
            bool hit = true;
            for (uint256 j; j < 20; ++j) {
                if (code[i + j] != beacon[j]) {
                    hit = false;
                    break;
                }
            }
            if (hit) {
                for (uint256 j; j < 20; ++j) {
                    code[i + j] = other[j];
                }
                ++replaced;
            }
        }
        assertEq(replaced, 1, "beacon embedded once");
        address fake = address(0xFA4E);
        vm.etch(fake, code);
        assertFalse(list.isGenuine(fake));
    }

    function test_launchFeeds_eightDecimalsNamedAndLive() public onlyFork {
        string[] memory tickers = vm.parseJsonStringArray(config, ".tickers");
        for (uint256 i; i < tickers.length; ++i) {
            AggregatorV3Interface f =
                AggregatorV3Interface(vm.parseJsonAddress(config, string.concat(".assets.", tickers[i], ".clFeed")));
            assertEq(f.decimals(), 8, tickers[i]);
            bytes32 d = keccak256(bytes(f.description()));
            assertTrue(
                d == keccak256(bytes(string.concat("RH", tickers[i], " / USD")))
                    || d == keccak256(bytes(string.concat("Robinhood ", tickers[i], " / USD"))),
                f.description()
            );
            (, int256 answer,,,) = f.latestRoundData();
            assertGt(answer, 0, tickers[i]);
        }
    }

    function test_setAsset_realTokensAndFeeds() public onlyFork {
        string[] memory tickers = vm.parseJsonStringArray(config, ".tickers");
        for (uint256 i; i < tickers.length; ++i) {
            string memory p = string.concat(".assets.", tickers[i]);
            list.setAsset(
                vm.parseJsonAddress(config, string.concat(p, ".token")),
                IStockTokenAllowList.Asset({
                    pythId: keccak256(bytes(tickers[i])),
                    clFeed: vm.parseJsonAddress(config, string.concat(p, ".clFeed")),
                    tickPrice8: 50_000_000,
                    budgetAbove: 2_000e6,
                    budgetRange: 2_000e6,
                    budgetUpDown: 2_000e6,
                    listed: true
                })
            );
        }
    }

    function test_soxxCarriesTheSplitMultiplier() public onlyFork {
        uint256 m = IStockToken(_token("SOXX")).uiMultiplier();
        assertGt(m, 3e18);
        assertLt(m, 3.05e18);
    }
}
