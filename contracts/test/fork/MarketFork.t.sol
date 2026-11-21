// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../../src/LMSRMarket.sol";
import {ILMSRMarket} from "../../src/interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "../../src/interfaces/IMarketFactory.sol";
import {IStockToken} from "../../src/interfaces/external/IStockToken.sol";
import {PriorMath} from "../../src/lib/PriorMath.sol";
import {MockHousePool} from "../mocks/MockHousePool.sol";
import {AggregatorV3Interface} from "@chainlink/AggregatorV3Interface.sol";
import {Test, console2} from "forge-std/Test.sol";
import {IEIP712} from "permit2/IEIP712.sol";
import {ISignatureTransfer} from "permit2/ISignatureTransfer.sol";
import {LibClone} from "solady/utils/LibClone.sol";

/// @notice LMSRMarket against chain 4663: real USDG, real NVDA stock token, canonical Permit2. Runs with `RPC_4663`
///         (archive RPC for a pinned `FORK_BLOCK`; else `latest`). Parts that the live chain cannot support are skipped
///         with a logged reason, never silently.
contract MarketForkTest is Test {
    address constant USDG_4663 = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    bytes32 constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    uint96 constant BUDGET = 2_000e6;
    // Not a well-known test key: the address of 0xA11CE carries code on 4663, so Permit2 would treat it as a contract.
    uint256 constant OWNER_PK = uint256(keccak256("closari.fork.owner"));

    bool internal enabled;
    string internal skipReason;
    address internal nvda;
    MockHousePool internal pool;
    LMSRMarket internal m;
    address internal alice = makeAddr("alice");
    address internal relayer = makeAddr("relayer");

    function setUp() public {
        string memory rpc = vm.envOr("RPC_4663", string(""));
        enabled = bytes(rpc).length != 0;
        if (!enabled) return;
        uint256 blk = vm.envOr("FORK_BLOCK", uint256(0));
        if (blk == 0) vm.createSelectFork(rpc);
        else vm.createSelectFork(rpc, blk);

        string memory config = vm.readFile(string.concat(vm.projectRoot(), "/config/assets.4663.json"));
        nvda = vm.parseJsonAddress(config, ".assets.NVDA.token");
        (, int256 answer,,,) =
            AggregatorV3Interface(vm.parseJsonAddress(config, ".assets.NVDA.clFeed")).latestRoundData();
        IStockToken tok = IStockToken(nvda);
        uint256 snap = tok.uiMultiplier();
        if (tok.oraclePaused() || tok.newUIMultiplier() != snap) {
            skipReason = "NVDA has its oracle paused or a pending multiplier change at this block (trading is closed)";
            return;
        }

        LMSRMarket impl = new LMSRMarket(USDG_4663, PERMIT2);
        pool = new MockHousePool();
        m = LMSRMarket(LibClone.clone(address(impl)));
        pool.allocate(address(m), BUDGET);
        m.initialize(_config(int64(answer), snap), address(pool), makeAddr("oracle"), makeAddr("router"), address(0));

        require(vm.addr(OWNER_PK).code.length == 0, "signer must be an EOA on the fork");
        if (!_tryDeal(address(m), BUDGET) || !_tryDeal(alice, 1_000e6) || !_tryDeal(vm.addr(OWNER_PK), 1_000e6)) {
            skipReason = "deal() cannot write USDG balances on this fork (proxy storage layout)";
            return;
        }
        vm.prank(alice);
        (bool ok,) = USDG_4663.call(abi.encodeWithSignature("approve(address,uint256)", address(m), type(uint256).max));
        require(ok, "approve");
    }

    modifier onlyFork() {
        if (!enabled) vm.skip(true);
        if (bytes(skipReason).length != 0) {
            console2.log("skipped:", skipReason);
            vm.skip(true);
        }
        _;
    }

    function _config(int64 ref8, uint256 snap) internal view returns (ILMSRMarket.Config memory c) {
        int64[] memory edges = new int64[](1);
        edges[0] = ref8;
        uint256[] memory prior = PriorMath.floorNormalize(PriorMath.raw(ref8, edges, 300));
        uint64 nowTs = uint64(block.timestamp);
        c.token = nvda;
        c.dayId = uint32(nowTs / 86_400);
        c.kind = IMarketFactory.Kind.ABOVE;
        c.n = 2;
        c.edges = edges;
        c.createdTs = nowTs;
        c.openTs = nowTs + 1 hours;
        c.haltTs = nowTs + 6 hours;
        c.closeTs = c.haltTs + 600;
        c.multiplierSnapshot = snap;
        c.bWad = PriorMath.liquidity(BUDGET, prior) * 1e12;
        c.budget = BUDGET;
        c.priorWad = prior;
        c.baseFeeBps = 50;
        c.rampMaxBps = 250;
    }

    function _tryDeal(address to, uint256 amount) internal returns (bool) {
        try this.dealUsdg(to, amount) {}
        catch {
            return false;
        }
        return _balance(to) == amount;
    }

    function dealUsdg(address to, uint256 amount) external {
        deal(USDG_4663, to, amount);
    }

    function _balance(address who) internal view returns (uint256) {
        (bool ok, bytes memory r) = USDG_4663.staticcall(abi.encodeWithSignature("balanceOf(address)", who));
        require(ok && r.length >= 32, "balanceOf");
        return abi.decode(r, (uint256));
    }

    function test_buyGasCold_thenSell() public onlyFork {
        // setUp ran in its own transaction; cool the touched accounts anyway so the buy pays first-touch prices.
        vm.cool(address(m));
        vm.cool(USDG_4663);
        vm.cool(nvda);
        vm.cool(address(pool));
        vm.prank(alice);
        uint256 g = gasleft();
        uint256 paid = m.buy(1, 10e6, type(uint256).max, type(uint64).max, address(0));
        g -= gasleft();
        emit log_named_uint("buy gas (fork, cold)", g);
        assertLt(g, 300_000);
        assertEq(m.shares(alice, 1), 10e6);
        assertEq(_balance(alice), 1_000e6 - paid);

        vm.prank(alice);
        uint256 got = m.sell(1, 5e6, 0, type(uint64).max, address(0));
        assertEq(m.shares(alice, 1), 5e6);
        assertEq(_balance(alice), 1_000e6 - paid + got);
        assertEq(pool.worst(address(m)), int256(m.cash() - m.liability()));
    }

    function test_permit2IsThePinnedCanonicalRuntime() public onlyFork {
        assertEq(PERMIT2.codehash, keccak256(vm.parseBytes(vm.readFile("test/fixtures/permit2.runtime.hex"))));
    }

    function test_buyWithAuthorization_realUsdg() public onlyFork {
        (bool ok, bytes memory r) = USDG_4663.staticcall(abi.encodeWithSignature("DOMAIN_SEPARATOR()"));
        if (!ok || r.length != 32) {
            console2.log("skipped: USDG has no DOMAIN_SEPARATOR() at this block");
            vm.skip(true);
        }
        bytes32 domain = abi.decode(r, (bytes32));
        address owner = vm.addr(OWNER_PK);
        ILMSRMarket.TradeIntent memory t = _intent(owner);
        bytes32 nonce = _intentHash(t);
        bytes32 structHash = keccak256(
            abi.encode(
                RECEIVE_WITH_AUTHORIZATION_TYPEHASH,
                owner,
                address(m),
                t.maxTotal,
                block.timestamp - 1,
                block.timestamp + 600,
                nonce
            )
        );
        (uint8 v, bytes32 rr, bytes32 s) =
            vm.sign(OWNER_PK, keccak256(abi.encodePacked("\x19\x01", domain, structHash)));
        uint256 before = _balance(owner);
        vm.prank(relayer);
        uint256 total = m.buyWithAuthorization(t, block.timestamp - 1, block.timestamp + 600, v, rr, s);
        assertEq(m.shares(owner, 1), 10e6);
        assertEq(m.shares(relayer, 1), 0);
        assertEq(before - _balance(owner), total); // excess over the cost refunded to the owner
    }

    function _intent(address owner) internal view returns (ILMSRMarket.TradeIntent memory) {
        return ILMSRMarket.TradeIntent({
            market: address(m),
            owner: owner,
            outcome: 1,
            shares: 10e6,
            maxTotal: 20e6,
            deadline: uint64(block.timestamp + 600),
            builder: address(0),
            salt: bytes32(uint256(7))
        });
    }

    function _intentHash(ILMSRMarket.TradeIntent memory t) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                m.TRADE_TYPEHASH(), t.market, t.owner, t.outcome, t.shares, t.maxTotal, t.deadline, t.builder, t.salt
            )
        );
    }

    function test_buyWithPermit2_realUsdgAndPermit2() public onlyFork {
        address owner = vm.addr(OWNER_PK);
        vm.prank(owner);
        (bool ok,) = USDG_4663.call(abi.encodeWithSignature("approve(address,uint256)", PERMIT2, type(uint256).max));
        require(ok, "approve permit2");
        ILMSRMarket.TradeIntent memory t = _intent(owner);
        ISignatureTransfer.PermitTransferFrom memory p = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: USDG_4663, amount: t.maxTotal}),
            nonce: 1,
            deadline: block.timestamp + 600
        });
        bytes32 typehash = keccak256(
            abi.encodePacked(
                "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,",
                m.WITNESS_TYPE_STRING()
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                typehash,
                keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, USDG_4663, t.maxTotal)),
                address(m),
                p.nonce,
                p.deadline,
                _intentHash(t)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(OWNER_PK, keccak256(abi.encodePacked("\x19\x01", IEIP712(PERMIT2).DOMAIN_SEPARATOR(), structHash)));
        uint256 before = _balance(owner);
        vm.prank(relayer);
        uint256 total = m.buyWithPermit2(t, p, abi.encodePacked(r, s, v));
        assertEq(m.shares(owner, 1), 10e6);
        assertEq(m.shares(relayer, 1), 0);
        assertEq(before - _balance(owner), total); // excess over the cost refunded to the owner
    }
}
