// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ExchangeCalendar} from "../src/ExchangeCalendar.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {StockTokenAllowList} from "../src/StockTokenAllowList.sol";
import {IExchangeCalendar} from "../src/interfaces/IExchangeCalendar.sol";
import {IStockTokenAllowList} from "../src/interfaces/IStockTokenAllowList.sol";
import {MockAggregator} from "../test/mocks/MockAggregator.sol";
import {MockBeacon} from "../test/mocks/MockBeacon.sol";
import {MockFeeRouter} from "../test/mocks/MockFeeRouter.sol";
import {MockHousePool} from "../test/mocks/MockHousePool.sol";
import {MockMarket} from "../test/mocks/MockMarket.sol";
import {MockSettlementOracle} from "../test/mocks/MockSettlementOracle.sol";
import {MockStockToken} from "../test/mocks/MockStockToken.sol";
import {MockPyth} from "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import {Script, console2} from "forge-std/Script.sol";
import {ERC7821} from "solady/accounts/ERC7821.sol";
import {Timelock} from "solady/accounts/Timelock.sol";

/// @notice M1 end-to-end on anvil (31337) or an anvil fork of 4663. Deploys MOCKS for pool/oracle/router/market:
///         never broadcast to a live chain. Guarded by CLOSARI_LOCAL_DEPLOY=true.
contract DeployLocal is Script {
    bytes32 constant MODE = 0x0100000000007821000100000000000000000000000000000000000000000000;
    // anvil default accounts 0, 1, 2 (public test keys)
    uint256 constant DEPLOYER_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant MULTISIG_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    address constant GUARDIAN = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address constant STAKING_PLACEHOLDER = address(0xC15A);
    address constant BEACON_4663 = 0xe10b6f6B275de231345c20D14Ab812db62151b00;

    struct Deployed {
        Timelock timelock;
        ExchangeCalendar calendar;
        StockTokenAllowList allowList;
        MarketFactory factory;
        MockPyth pyth;
        address nvda;
    }

    function run() external returns (Deployed memory dep) {
        require(vm.envOr("CLOSARI_LOCAL_DEPLOY", false), "DeployLocal: set CLOSARI_LOCAL_DEPLOY=true (mocks only)");
        require(block.chainid == 31337 || block.chainid == 4663, "DeployLocal: anvil or anvil --fork-url 4663 only");
        address deployer = vm.addr(DEPLOYER_PK);
        address multisig = vm.addr(MULTISIG_PK);

        vm.startBroadcast(DEPLOYER_PK);
        dep = _deploy(deployer, multisig);
        vm.stopBroadcast();

        vm.startBroadcast(MULTISIG_PK);
        _seed(dep);
        vm.stopBroadcast();

        uint32 dayId = _nextListableDay(dep.calendar);
        bytes[] memory u = new bytes[](1);
        u[0] = dep.pyth
            .createPriceFeedUpdateData(
                keccak256("local:NVDA"),
                18_812_000_000,
                9_000_000,
                -8,
                18_812_000_000,
                9_000_000,
                uint64(block.timestamp),
                uint64(block.timestamp) - 1
            );
        vm.startBroadcast(DEPLOYER_PK);
        address[] memory markets = dep.factory.listDay{value: 1}(dep.nvda, dayId, u);
        vm.stopBroadcast();

        // Post-deploy assertions (the brief's "deployer has no roles").
        for (uint256 role; role <= 3; ++role) {
            require(!dep.timelock.hasRole(deployer, role), "deployer holds a timelock role");
        }
        require(dep.factory.timelock() == address(dep.timelock), "factory timelock");
        require(dep.factory.guardian() == GUARDIAN, "factory guardian");
        require(address(dep.calendar.factory()) == address(dep.factory), "calendar factory link");
        require(markets.length == 8, "8 markets");

        console2.log("timelock ", address(dep.timelock));
        console2.log("calendar ", address(dep.calendar));
        console2.log("allowList", address(dep.allowList));
        console2.log("factory  ", address(dep.factory));
        console2.log("listed NVDA dayId", dayId, "markets", markets.length);
    }

    function _deploy(address deployer, address multisig) internal returns (Deployed memory dep) {
        address[] memory roles = new address[](1);
        roles[0] = multisig;
        dep.timelock = new Timelock();
        dep.timelock.initialize(0, address(0), roles, roles, roles); // local: no delay; production: 48 h

        address beacon;
        bytes32 codehash;
        if (block.chainid == 4663) {
            beacon = BEACON_4663;
            dep.nvda = _cfgAddress(".assets.NVDA.token");
            codehash = dep.nvda.codehash;
        } else {
            beacon = address(new MockBeacon(address(0x1111)));
            dep.nvda = address(new MockStockToken(1e18));
            codehash = dep.nvda.codehash;
        }
        dep.pyth = new MockPyth(120, 1);
        address pool = address(new MockHousePool());
        address oracle = address(new MockSettlementOracle());
        address router = address(new MockFeeRouter());
        address impl = address(new MockMarket());

        address predicted = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 2);
        dep.calendar = new ExchangeCalendar(address(dep.timelock), predicted);
        dep.allowList = new StockTokenAllowList(beacon, codehash, address(dep.timelock));
        dep.factory = new MarketFactory(
            MarketFactory.Params({
                calendar: address(dep.calendar),
                allowList: address(dep.allowList),
                pool: pool,
                oracle: oracle,
                router: router,
                staking: STAKING_PLACEHOLDER,
                pyth: address(dep.pyth),
                marketImpl: impl,
                timelock: address(dep.timelock),
                guardian: GUARDIAN
            })
        );
        require(address(dep.factory) == predicted, "factory address prediction");
    }

    /// @dev Calendar (all vector sessions) and assets, both through the timelock.
    function _seed(Deployed memory dep) internal {
        string memory cal = vm.readFile(string.concat(vm.projectRoot(), "/test/vectors/calendar.json"));
        uint256[] memory d = vm.parseJsonUintArray(cal, ".dayIds");
        uint256[] memory o = vm.parseJsonUintArray(cal, ".openTs");
        uint256[] memory c = vm.parseJsonUintArray(cal, ".closeTs");
        uint32[] memory ds = new uint32[](d.length);
        IExchangeCalendar.Session[] memory ss = new IExchangeCalendar.Session[](d.length);
        for (uint256 i; i < d.length; ++i) {
            ds[i] = uint32(d[i]);
            ss[i] = IExchangeCalendar.Session(uint64(o[i]), uint64(c[i]));
        }
        _viaTimelock(
            dep.timelock, address(dep.calendar), abi.encodeCall(ExchangeCalendar.setSessions, (ds, ss)), "calendar"
        );

        if (block.chainid == 4663) {
            string[] memory tickers = vm.parseJsonStringArray(_cfg(), ".tickers");
            for (uint256 i; i < tickers.length; ++i) {
                string memory p = string.concat(".assets.", tickers[i]);
                _setAsset(
                    dep, _cfgAddress(string.concat(p, ".token")), _cfgAddress(string.concat(p, ".clFeed")), tickers[i]
                );
            }
        } else {
            _setAsset(dep, dep.nvda, address(new MockAggregator(8, "RHNVDA / USD")), "NVDA");
        }
    }

    function _setAsset(Deployed memory dep, address token, address clFeed, string memory ticker) internal {
        IStockTokenAllowList.Asset memory a = IStockTokenAllowList.Asset({
            pythId: keccak256(bytes(string.concat("local:", ticker))),
            clFeed: clFeed,
            tickPrice8: 50_000_000,
            budgetAbove: 2_000e6,
            budgetRange: 2_000e6,
            budgetUpDown: 2_000e6,
            listed: true
        });
        _viaTimelock(
            dep.timelock, address(dep.allowList), abi.encodeCall(StockTokenAllowList.setAsset, (token, a)), ticker
        );
    }

    function _viaTimelock(Timelock tl, address to, bytes memory data, string memory salt) internal {
        ERC7821.Call[] memory calls = new ERC7821.Call[](1);
        calls[0] = ERC7821.Call({to: to, value: 0, data: data});
        bytes memory exec = abi.encode(calls, abi.encode(bytes32(0), keccak256(bytes(salt))));
        tl.propose(MODE, exec, 0);
        tl.execute(MODE, exec);
    }

    /// @dev First day that listDay accepts now: has a session, now < close - 4200 (TooLate), and the previous
    ///      trading day's close has passed (TooEarly, interface change 2026-11-21).
    function _nextListableDay(ExchangeCalendar cal) internal view returns (uint32) {
        uint32 today = uint32(block.timestamp / 86_400);
        for (uint32 d = today; d < today + 10; ++d) {
            IExchangeCalendar.Session memory s = cal.session(d);
            if (s.closeTs == 0 || block.timestamp + 4_200 >= s.closeTs) continue;
            uint32 prev = cal.prevTradingDay(d, 10);
            if (prev == 0 || cal.session(prev).closeTs <= block.timestamp) return d;
        }
        revert("no listable day in the next 10 days (now may be between a close-4200 cutoff and the close)");
    }

    function _cfg() internal view returns (string memory) {
        return vm.readFile(string.concat(vm.projectRoot(), "/config/assets.4663.json"));
    }

    function _cfgAddress(string memory key) internal view returns (address) {
        return vm.parseJsonAddress(_cfg(), key);
    }
}
