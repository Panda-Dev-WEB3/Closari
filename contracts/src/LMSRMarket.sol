// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IClsrStaking} from "./interfaces/IClsrStaking.sol";
import {IHousePool} from "./interfaces/IHousePool.sol";
import {ILMSRMarket} from "./interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "./interfaces/IMarketFactory.sol";
import {IStockToken} from "./interfaces/external/IStockToken.sol";
import {Constants} from "./lib/Constants.sol";
import {LMSRMath} from "./lib/LMSRMath.sol";
import {ISignatureTransfer} from "permit2/ISignatureTransfer.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @notice Fixed-b LMSR market, seeded with a prior (M2 spec §3). Clone implementation: clones share USDG and
///         PERMIT2 through this contract's immutables. Settlement (resolve/void/claim/sweep/pullFees) lands in M3.
contract LMSRMarket is ILMSRMarket, ReentrancyGuardTransient {
    using SafeTransferLib for address;

    bytes32 public constant TRADE_TYPEHASH = keccak256(
        "ClosariTrade(address market,address owner,uint8 outcome,uint256 shares,uint256 maxTotal,uint64 deadline,address builder,bytes32 salt)"
    );
    string public constant WITNESS_TYPE_STRING =
        "ClosariTrade witness)ClosariTrade(address market,address owner,uint8 outcome,uint256 shares,uint256 maxTotal,uint64 deadline,address builder,bytes32 salt)TokenPermissions(address token,uint256 amount)";
    uint256 internal constant STAKING_GAS = 50_000;
    uint256 internal constant MAX_TRADE_B = 20;

    address public immutable USDG;
    address public immutable PERMIT2;

    struct Core {
        address token;
        uint32 dayId;
        IMarketFactory.Kind kind;
        uint8 n;
        State state;
        bool initialized;
        bool openRecorded;
    }

    struct Times {
        uint64 createdTs;
        uint64 openTs;
        uint64 haltTs;
        uint64 closeTs;
    }

    struct Money {
        uint128 bWad;
        uint96 budget;
        uint16 baseFeeBps;
        uint16 rampMaxBps;
    }

    struct Fill {
        uint256 gross;
        uint256 fee;
        int256 dWorst;
        int256 dBest;
    }

    Core internal _core;
    Times internal _t;
    Money internal _m;
    uint256 internal _snapshot; // multiplier snapshot (compared only, never used in arithmetic: I11)
    address public factory;
    address public pool;
    address public oracle;
    address public router;
    address public staking;
    int64[] internal _edges;
    uint256[] internal _prior;

    uint256[8] internal _x; // WAD quantities, including the virtual house quantities
    uint256[8] internal _x0; // virtual house quantities (owed to nobody)

    uint256 public cash;
    uint256 public feeEscrow;
    uint256 public builderFeesTotal;
    mapping(address => mapping(uint8 => uint256)) public shares;
    mapping(address => uint256) public feesPaid;
    mapping(address => uint256) public feesByBuilder;
    mapping(address => mapping(uint8 => uint256)) public lateBought;

    // Price accumulator: cumulative floored price × seconds for outcomes 0..n−2, uint128 each, two per slot.
    uint256[4] internal _cum;
    uint64 internal _lastTs;
    uint64[2] internal _cpTs;
    bool[2] internal _cpDone;
    uint256[4][2] internal _cp;

    constructor(address usdg, address permit2) {
        USDG = usdg;
        PERMIT2 = permit2;
        _core.initialized = true; // the implementation itself can never be initialised (M1 obligation 6)
    }

    function _useTransientReentrancyGuardOnlyOnMainnet() internal pure override returns (bool) {
        return false; // 4663 supports TSTORE
    }

    // ------------------------------------------------------------------ init

    function initialize(Config calldata c, address pool_, address oracle_, address router_, address staking_) external {
        if (_core.initialized) revert AlreadyInitialized();
        uint256 n = c.n;
        if (
            n < 2 || n > 8 || c.priorWad.length != n || c.bWad == 0 || c.bWad > type(uint128).max
                || c.createdTs >= c.haltTs || c.haltTs >= c.closeTs || c.baseFeeBps > Constants.MAX_BASE_FEE_BPS
                || c.rampMaxBps > Constants.MAX_RAMP_BPS || pool_ == address(0) || oracle_ == address(0)
        ) revert BadConfig();
        uint256 sum = 0;
        uint256 pMin = type(uint256).max;
        for (uint256 i; i < n; ++i) {
            uint256 p = c.priorWad[i];
            if (p < Constants.PRIOR_MIN) revert BadConfig();
            sum += p;
            if (p < pMin) pMin = p;
            _prior.push(p);
        }
        if (sum != 1e18) revert BadConfig();

        _core = Core(c.token, c.dayId, c.kind, c.n, State.Trading, true, false);
        _t = Times(c.createdTs, c.openTs, c.haltTs, c.closeTs);
        _m = Money(uint128(c.bWad), c.budget, c.baseFeeBps, c.rampMaxBps);
        _snapshot = c.multiplierSnapshot;
        for (uint256 i; i < c.edges.length; ++i) {
            _edges.push(c.edges[i]);
        }
        (factory, pool, oracle, router, staking) = (msg.sender, pool_, oracle_, router_, staking_);

        // q0_i = b·ln(p_i / p_min) ≥ 0, so prices start at the prior (M2 spec §3).
        for (uint256 i; i < n; ++i) {
            int256 l = FixedPointMathLib.lnWad(int256(FixedPointMathLib.divWad(c.priorWad[i], pMin)));
            uint256 x0 = FixedPointMathLib.mulDiv(c.bWad, uint256(l), 1e18);
            _x0[i] = x0;
            _x[i] = x0;
        }
        cash = c.budget;
        _lastTs = c.createdTs;
        uint64 w = Constants.VOID_TWAP_WINDOW;
        _cpTs[0] = c.haltTs - w > c.createdTs ? c.haltTs - w : c.createdTs;
        if (c.kind == IMarketFactory.Kind.UPDOWN) {
            _cpTs[1] = c.openTs > c.createdTs + w ? c.openTs - w : c.createdTs;
        }
    }

    // ------------------------------------------------------------------ views

    function config() external view returns (Config memory c) {
        Core memory co = _core;
        Times memory t = _t;
        Money memory mo = _m;
        c.token = co.token;
        c.dayId = co.dayId;
        c.kind = co.kind;
        c.n = co.n;
        c.edges = _edges;
        c.createdTs = t.createdTs;
        c.openTs = t.openTs;
        c.haltTs = t.haltTs;
        c.closeTs = t.closeTs;
        c.multiplierSnapshot = _snapshot;
        c.bWad = mo.bWad;
        c.budget = mo.budget;
        c.priorWad = _prior;
        c.baseFeeBps = mo.baseFeeBps;
        c.rampMaxBps = mo.rampMaxBps;
    }

    function state() external view returns (State) {
        return _core.state;
    }

    function prices() public view returns (uint256[] memory) {
        return LMSRMath.prices(_xs(), _m.bWad);
    }

    function quoteBuy(uint8 outcome, uint256 sh, address account) external view returns (uint256 gross, uint256 fee) {
        _checkSize(outcome, sh);
        gross = LMSRMath.buyCost(_xs(), _m.bWad, outcome, sh);
        fee = _fee(gross, account);
    }

    function quoteSell(uint8 outcome, uint256 sh, address account) external view returns (uint256 gross, uint256 fee) {
        _checkSize(outcome, sh);
        gross = LMSRMath.sellProceeds(_xs(), _m.bWad, outcome, sh);
        fee = _fee(gross, account);
    }

    function liability() external view returns (uint256 hi) {
        (hi,) = _liab(_xs());
    }

    function cumulativeAt(uint64 ts) public view returns (uint256[] memory) {
        uint64 last = _lastTs;
        if (ts < last) revert BadTimestamp();
        uint256 n = _core.n;
        return _unpack(_advance(_cum, prices(), n, ts - last), n, ts - _t.createdTs);
    }

    function checkpoints() external view returns (uint64[2] memory ts, uint256[][2] memory cum) {
        uint256 n = _core.n;
        for (uint256 j; j < 2; ++j) {
            ts[j] = _cpTs[j];
            if (ts[j] == 0) continue;
            cum[j] = _cpDone[j] ? _unpack(_cp[j], n, ts[j] - _t.createdTs) : cumulativeAt(ts[j]);
        }
    }

    // ------------------------------------------------------------------ trading

    function buy(uint8 outcome, uint256 sh, uint256 maxTotal, uint64 deadline, address builder)
        external
        nonReentrant
        returns (uint256 total)
    {
        Fill memory f = _trade(msg.sender, outcome, sh, true, builder, deadline);
        total = f.gross + f.fee;
        if (total > maxTotal) revert Slippage();
        USDG.safeTransferFrom(msg.sender, address(this), total);
        _mark(f);
    }

    function buyWithAuthorization(TradeIntent calldata, uint256, uint256, uint8, bytes32, bytes32)
        external
        pure
        returns (uint256)
    {
        revert NotYetImplemented(); // Task 6
    }

    function buyWithPermit2(TradeIntent calldata, ISignatureTransfer.PermitTransferFrom calldata, bytes calldata)
        external
        pure
        returns (uint256)
    {
        revert NotYetImplemented(); // Task 6
    }

    function sell(uint8 outcome, uint256 sh, uint256 minNet, uint64 deadline, address builder)
        external
        nonReentrant
        returns (uint256 net)
    {
        Fill memory f = _trade(msg.sender, outcome, sh, false, builder, deadline);
        net = f.gross - f.fee;
        if (net < minNet) revert Slippage();
        USDG.safeTransfer(msg.sender, net); // a frozen seller reverts here; nobody else is affected
        _mark(f);
    }

    // ------------------------------------------------------------------ settlement hooks

    function setOpenReference(int64 openPrice8, uint64) external {
        if (msg.sender != oracle) revert NotOracle();
        if (_core.kind != IMarketFactory.Kind.UPDOWN) revert NotUpDown();
        if (_core.openRecorded) revert OpenAlreadySet();
        if (_core.state != State.Trading) revert NotTrading();
        if (openPrice8 <= 0) revert BadConfig();
        _roll(prices(), _core.n);
        _edges.push(openPrice8);
        _core.openRecorded = true;
    }

    function resolve(uint8, int64) external pure {
        revert NotYetImplemented();
    }

    function voidMarket(uint8) external pure {
        revert NotYetImplemented();
    }

    function claim(address) external pure returns (uint256) {
        revert NotYetImplemented();
    }

    function claimMany(address[] calldata) external pure {
        revert NotYetImplemented();
    }

    function sweep() external pure {
        revert NotYetImplemented();
    }

    function pullFees() external pure returns (uint256) {
        revert NotYetImplemented();
    }

    // ------------------------------------------------------------------ internals

    function _trade(address owner, uint8 k, uint256 sh, bool isBuy, address builder, uint64 deadline)
        internal
        returns (Fill memory f)
    {
        _guard(deadline);
        _checkSize(k, sh);
        uint256 bW = _m.bWad;
        uint256[] memory x = _xs();
        {
            (uint256 hi0, uint256 lo0) = _liab(x);
            f.dWorst = int256(cash - hi0); // held as the pre-trade values until the end
            f.dBest = int256(cash - lo0);
        }
        _roll(LMSRMath.prices(x, bW), _core.n);

        uint256 cash1 = _applyFill(owner, k, sh, isBuy, x, bW, f);
        _lateHour(owner, k, sh, isBuy, bW);

        uint256[] memory p = LMSRMath.prices(x, bW);
        for (uint256 i; i < p.length; ++i) {
            if (p[i] < Constants.P_MIN || p[i] > 1e18 - Constants.P_MIN) revert PriceOutOfBounds();
        }
        _x[k] = x[k];
        cash = cash1;

        f.fee = _fee(f.gross, owner);
        _bookFee(owner, builder, f.fee);

        (uint256 hi1, uint256 lo1) = _liab(x);
        assert(cash1 >= hi1); // I1′: cash covers the largest trader liability
        f.dWorst = int256(cash1 - hi1) - f.dWorst;
        f.dBest = int256(cash1 - lo1) - f.dBest;
        emit Trade(owner, k, isBuy, sh, f.gross, f.fee, builder, p);
    }

    /// @dev Moves x[k] (memory only) and the trader's shares; returns the post-trade cash.
    function _applyFill(address owner, uint8 k, uint256 sh, bool isBuy, uint256[] memory x, uint256 bW, Fill memory f)
        internal
        returns (uint256 cash1)
    {
        if (isBuy) {
            f.gross = LMSRMath.buyCost(x, bW, k, sh);
            x[k] += sh * 1e12;
            if (x[k] / 1e12 > type(uint128).max) revert TradeTooLarge();
            shares[owner][k] += sh;
            cash1 = cash + f.gross;
        } else {
            uint256 held = shares[owner][k];
            if (held < sh) revert InsufficientShares();
            f.gross = LMSRMath.sellProceeds(x, bW, k, sh);
            x[k] -= sh * 1e12;
            shares[owner][k] = held - sh;
            cash1 = cash - f.gross;
        }
    }

    function _bookFee(address owner, address builder, uint256 fee) internal {
        // slither-disable-next-line incorrect-equality -- triaged, security/triage.md T5
        if (fee == 0) return;
        feeEscrow += fee;
        feesPaid[owner] += fee;
        if (builder != address(0)) {
            feesByBuilder[builder] += fee;
            builderFeesTotal += fee;
        }
    }

    function _mark(Fill memory f) internal {
        if (f.dWorst != 0 || f.dBest != 0) IHousePool(pool).onMark(f.dWorst, f.dBest);
    }

    function _guard(uint64 deadline) internal view {
        if (_core.state != State.Trading) revert NotTrading();
        if (block.timestamp >= _t.haltTs) revert Halted();
        if (block.timestamp > deadline) revert Expired();
        if (_caVoidVisible()) revert CorporateActionVisible();
        if (_core.kind == IMarketFactory.Kind.UPDOWN && block.timestamp >= _t.openTs && !_core.openRecorded) {
            revert AwaitingOpen();
        }
    }

    /// @dev The settlement-time CA void condition (Backend §3.4 audit fix), evaluated before every trade (I16).
    function _caVoidVisible() internal view returns (bool) {
        IStockToken tok = IStockToken(_core.token);
        uint256 snap = _snapshot;
        if (tok.uiMultiplier() != snap || tok.oraclePaused()) return true;
        if (tok.newUIMultiplier() != snap) {
            uint256 at = tok.effectiveAt();
            return at >= _t.createdTs && at <= uint256(_t.closeTs) + Constants.CA_AFTER;
        }
        return false;
    }

    function _checkSize(uint8 k, uint256 sh) internal view {
        if (k >= _core.n) revert BadOutcome();
        if (sh == 0) revert ZeroShares();
        if (sh * 1e12 > uint256(_m.bWad) * MAX_TRADE_B) revert TradeTooLarge();
    }

    function _lateHour(address owner, uint8 k, uint256 sh, bool isBuy, uint256 bW) internal {
        if (block.timestamp < _t.closeTs - Constants.LATE_HOUR) return;
        uint256 used = lateBought[owner][k];
        if (isBuy) {
            used += sh;
            if (used * 4e12 > bW) revert LateHourCap(); // ≤ b/4 shares
        } else {
            used = used > sh ? used - sh : 0;
        }
        lateBought[owner][k] = used;
    }

    function _fee(uint256 gross, address account) internal view returns (uint256) {
        uint256 base = _m.baseFeeBps;
        uint256 bps = base * (10_000 - _discount(account)) / 10_000 + _ramp();
        return FixedPointMathLib.mulDivUp(gross, bps, 10_000);
    }

    function _ramp() internal view returns (uint256) {
        uint256 halt = _t.haltTs;
        uint256 start = halt - Constants.RAMP_WINDOW;
        if (block.timestamp < start) return 0;
        if (block.timestamp >= halt) return _m.rampMaxBps;
        return uint256(_m.rampMaxBps) * (block.timestamp - start) / Constants.RAMP_WINDOW;
    }

    /// @dev Gas-capped, returndata-bounded read. Any failure, a missing contract or a value above the cap counts as 0,
    ///      so a broken staking contract can never stop trading.
    function _discount(address account) internal view returns (uint256 d) {
        address s = staking;
        if (s == address(0)) return 0;
        bytes memory data = abi.encodeCall(IClsrStaking.discountBps, (account));
        bool ok;
        assembly ("memory-safe") {
            ok := staticcall(STAKING_GAS, s, add(data, 0x20), mload(data), 0x00, 0x20)
            if lt(returndatasize(), 0x20) { ok := 0 }
            d := mload(0x00)
        }
        if (!ok || d > Constants.MAX_DISCOUNT_BPS) return 0;
    }

    function _xs() internal view returns (uint256[] memory x) {
        uint256 n = _core.n;
        x = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            x[i] = _x[i];
        }
    }

    /// @dev Largest and smallest trader liability t_i = (x_i − x0_i) / 1e12, base units.
    function _liab(uint256[] memory x) internal view returns (uint256 hi, uint256 lo) {
        lo = type(uint256).max;
        for (uint256 i; i < x.length; ++i) {
            uint256 t = (x[i] - _x0[i]) / 1e12;
            if (t > hi) hi = t;
            if (t < lo) lo = t;
        }
    }

    function _roll(uint256[] memory p, uint256 n) internal {
        uint64 last = _lastTs;
        uint64 nowTs = uint64(block.timestamp);
        if (nowTs <= last) return;
        uint256[4] memory cum = _cum;
        for (uint256 j; j < 2; ++j) {
            uint64 cp = _cpTs[j];
            if (cp != 0 && !_cpDone[j] && cp <= nowTs) {
                _cp[j] = _advance(cum, p, n, cp - last);
                _cpDone[j] = true;
            }
        }
        _cum = _advance(cum, p, n, nowTs - last);
        _lastTs = nowTs;
    }

    function _advance(uint256[4] memory cum, uint256[] memory p, uint256 n, uint256 dt)
        internal
        pure
        returns (uint256[4] memory out)
    {
        for (uint256 i; i + 1 < n; ++i) {
            uint256 slot = i >> 1;
            uint256 shift = (i & 1) * 128;
            uint256 v = uint256(uint128(cum[slot] >> shift)) + p[i] * dt;
            out[slot] |= uint256(SafeCastLib.toUint128(v)) << shift;
        }
    }

    function _unpack(uint256[4] memory cum, uint256 n, uint256 elapsed) internal pure returns (uint256[] memory c) {
        c = new uint256[](n);
        uint256 s = 0;
        for (uint256 i; i + 1 < n; ++i) {
            c[i] = uint128(cum[i >> 1] >> ((i & 1) * 128));
            s += c[i];
        }
        c[n - 1] = elapsed * 1e18 - s;
    }
}
