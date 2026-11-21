// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IExchangeCalendar} from "./interfaces/IExchangeCalendar.sol";
import {IFeeRouter} from "./interfaces/IFeeRouter.sol";
import {IHousePool} from "./interfaces/IHousePool.sol";
import {ILMSRMarket} from "./interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "./interfaces/IMarketFactory.sol";
import {ISettlementOracle} from "./interfaces/ISettlementOracle.sol";
import {IStockTokenAllowList} from "./interfaces/IStockTokenAllowList.sol";
import {IStockToken} from "./interfaces/external/IStockToken.sol";
import {Constants} from "./lib/Constants.sol";
import {PriceMath} from "./lib/PriceMath.sol";
import {StrikeMath} from "./lib/StrikeMath.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @notice Permissionless daily listing of template markets per stock token (Backend §3.3, audit fixes included).
contract MarketFactory is IMarketFactory, ReentrancyGuard {
    struct Params {
        address calendar;
        address allowList;
        address pool;
        address oracle;
        address router;
        address staking;
        address pyth;
        address marketImpl;
        address timelock;
        address guardian;
    }

    /// @dev One market to open; keeps _open's stack small.
    struct Spec {
        address token;
        uint32 dayId;
        uint256 index;
        Kind kind;
        int64[] edges;
        uint96 budget;
    }

    error ZeroAddress();

    uint64 internal constant NO_LISTING_BEFORE_HALT = 3_600;
    uint32 internal constant CALENDAR_LOOKBACK = 10;
    uint256 internal constant REF_TRADING_DAYS = 3;
    uint64 internal constant REF_MAX_AGE = 120;
    uint256 internal constant REF_CONF_MAX_BPS = 50;
    uint256 internal constant MAX_STRIKES = 8;
    uint256 internal constant MAX_EDGES = 7;
    uint96 internal constant MAX_LISTING_BOUNTY = 5e6;
    uint96 internal constant LAUNCH_LISTING_BOUNTY = 1e6;

    uint8 internal constant SKIP_COLLAPSED = 1;
    uint8 internal constant SKIP_BUDGET = 2;
    uint8 internal constant SKIP_POOL_REFUSED = 3;
    uint8 internal constant SKIP_NO_EDGE = 4;
    uint8 internal constant SKIP_AFTER_OPEN = 5;

    IExchangeCalendar public immutable calendar;
    IStockTokenAllowList public immutable allowList;
    IHousePool public immutable pool;
    ISettlementOracle public immutable oracle;
    IFeeRouter public immutable router;
    address public immutable staking;
    IPyth public immutable pyth;
    address public immutable marketImpl;
    address public immutable timelock;
    address public immutable guardian;

    bool public listingPaused;
    uint96 public listingBounty;
    uint16 internal _baseFeeBps;
    uint16 internal _rampMaxBps;
    bool internal _upDown;
    int16[] internal _strikeBps;
    int16[] internal _edgeBps;

    mapping(address => mapping(uint32 => DayInfo)) internal _days;
    mapping(address => mapping(uint32 => bool)) public isSkipped;
    mapping(address => bool) public isMarket;
    mapping(uint32 => bool) public hasMarkets;

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert NotTimelock();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    constructor(Params memory p) {
        if (
            p.calendar == address(0) || p.allowList == address(0) || p.pool == address(0) || p.oracle == address(0)
                || p.router == address(0) || p.staking == address(0) || p.pyth == address(0)
                || p.marketImpl == address(0) || p.timelock == address(0) || p.guardian == address(0)
        ) revert ZeroAddress();
        calendar = IExchangeCalendar(p.calendar);
        allowList = IStockTokenAllowList(p.allowList);
        pool = IHousePool(p.pool);
        oracle = ISettlementOracle(p.oracle);
        router = IFeeRouter(p.router);
        staking = p.staking;
        pyth = IPyth(p.pyth);
        marketImpl = p.marketImpl;
        timelock = p.timelock;
        guardian = p.guardian;

        int16[] memory s = new int16[](6);
        (s[0], s[1], s[2], s[3], s[4], s[5]) = (-500, -200, -100, 100, 200, 500);
        int16[] memory e = new int16[](4);
        (e[0], e[1], e[2], e[3]) = (-200, -50, 50, 200);
        _setTemplate(s, e, true);
        listingBounty = LAUNCH_LISTING_BOUNTY;
        emit ListingBountySet(LAUNCH_LISTING_BOUNTY);
        _baseFeeBps = 50;
        _rampMaxBps = 250;
        emit FeesSet(50, 250);
    }

    // ------------------------------------------------------------------ listing

    // slither-disable-next-line reentrancy-eth -- triaged, security/triage.md T1
    function listDay(address token, uint32 dayId, bytes[] calldata refPythUpdate)
        external
        payable
        nonReentrant
        returns (address[] memory markets)
    {
        if (listingPaused) revert ListingIsPaused();
        DayInfo storage day = _days[token][dayId];
        if (day.createdTs != 0) revert AlreadyListed(token, dayId);
        if (isSkipped[token][dayId]) revert DaySkipped(token, dayId);
        IStockTokenAllowList.Asset memory a = allowList.asset(token);
        if (!a.listed || !allowList.isGenuine(token)) revert AssetNotListed(token);
        IExchangeCalendar.Session memory s = calendar.session(dayId);
        if (s.closeTs == 0) revert NoSession(dayId);
        uint32 prev = calendar.prevTradingDay(dayId, CALENDAR_LOOKBACK);
        if (prev != 0 && block.timestamp < calendar.session(prev).closeTs) revert TooEarly(dayId);
        if (block.timestamp + Constants.HALT_BEFORE_CLOSE + NO_LISTING_BEFORE_HALT >= s.closeTs) revert TooLate(dayId);
        uint256 mult = _checkCorporateActions(token, s.closeTs);
        if (pool.maturedQueuePending()) revert QueuePending();
        (int256 ref8, uint256 fee) = _reference(token, dayId, a.pythId, mult, refPythUpdate);

        day.createdTs = uint64(block.timestamp);
        day.openTs = s.openTs;
        day.closeTs = s.closeTs;
        day.pythId = a.pythId;
        day.clFeed = a.clFeed;
        day.multiplierSnapshot = mult;
        day.refPrice8 = SafeCastLib.toInt64(ref8);
        hasMarkets[dayId] = true;

        markets = _createMarkets(token, dayId, a);
        if (!_anyOpened(markets)) revert NoMarketsOpened(token, dayId);
        day.markets = markets;
        if (listingBounty != 0) router.creditBounty(msg.sender, listingBounty);
        emit DayListed(token, dayId, day.refPrice8, mult, markets);
        if (msg.value > fee) SafeTransferLib.safeTransferETH(msg.sender, msg.value - fee);
    }

    function _checkCorporateActions(address token, uint64 closeTs) internal view returns (uint256 mult) {
        IStockToken t = IStockToken(token);
        if (t.oraclePaused()) revert OraclePaused(token);
        mult = t.uiMultiplier();
        if (t.newUIMultiplier() != mult && t.effectiveAt() <= closeTs + Constants.CA_AFTER) {
            revert CorporateActionPending(token);
        }
    }

    /// @dev Last final, non-void close within 3 trading days (rescaled to today's multiplier); a listed day that is
    ///      not final blocks; otherwise a fresh Pyth price is required.
    function _reference(address token, uint32 dayId, bytes32 pythId, uint256 mult, bytes[] calldata upd)
        internal
        returns (int256 ref8, uint256 fee)
    {
        uint32 d = dayId;
        for (uint256 i; i < REF_TRADING_DAYS; ++i) {
            d = calendar.prevTradingDay(d, CALENDAR_LOOKBACK);
            if (d == 0) break;
            DayInfo storage prev = _days[token][d];
            if (prev.createdTs == 0) continue;
            ISettlementOracle.PriceResult memory r = oracle.closeResult(token, d);
            if (!r.final_) revert PreviousDayNotFinal(token, d);
            if (r.dayVoid == ISettlementOracle.VoidReason.NONE && r.price8 > 0) {
                return (PriceMath.rescale(r.price8, mult, prev.multiplierSnapshot), 0);
            }
        }
        return _referenceFromPyth(pythId, mult, upd);
    }

    function _referenceFromPyth(bytes32 pythId, uint256 mult, bytes[] calldata upd)
        internal
        returns (int256 ref8, uint256 fee)
    {
        if (upd.length == 0) revert ReferenceUpdateRequired();
        fee = pyth.getUpdateFee(upd);
        if (msg.value < fee) revert InsufficientFee(fee);
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = pythId;
        uint64 nowTs = uint64(block.timestamp);
        PythStructs.PriceFeed[] memory feeds =
            pyth.parsePriceFeedUpdates{value: fee}(upd, ids, nowTs - REF_MAX_AGE, nowTs);
        if (feeds[0].id != pythId) revert WrongFeed(feeds[0].id);
        (int256 p8, uint256 c8) = PriceMath.to8(feeds[0].price.price, feeds[0].price.conf, feeds[0].price.expo);
        if (p8 <= 0) revert BadReferencePrice();
        if (c8 * 10_000 > uint256(p8) * REF_CONF_MAX_BPS) revert ReferenceConfidenceTooWide();
        ref8 = PriceMath.toTokenTerms(p8, mult);
    }

    function _createMarkets(address token, uint32 dayId, IStockTokenAllowList.Asset memory a)
        internal
        returns (address[] memory markets)
    {
        int16[] memory sb = _strikeBps;
        int16[] memory eb = _edgeBps;
        bool upDown = _upDown;
        uint256 nAbove = sb.length;
        markets = new address[](nAbove + (eb.length != 0 ? 1 : 0) + (upDown ? 1 : 0));
        int256 ref8 = _days[token][dayId].refPrice8;

        int64[] memory strikes = StrikeMath.positional(ref8, sb, a.tickPrice8);
        for (uint256 i; i < nAbove; ++i) {
            int64[] memory edge = new int64[](1);
            edge[0] = strikes[i];
            Spec memory sp = Spec(token, dayId, i, Kind.ABOVE, edge, a.budgetAbove);
            // slither-disable-next-line incorrect-equality -- triaged, security/triage.md T3
            if (strikes[i] == 0) _skipped(sp, SKIP_COLLAPSED);
            else markets[i] = _open(sp);
        }
        uint256 idx = nAbove;
        if (eb.length != 0) {
            int64[] memory edges = StrikeMath.compact(StrikeMath.positional(ref8, eb, a.tickPrice8));
            Spec memory sp = Spec(token, dayId, idx, Kind.RANGE, edges, a.budgetRange);
            // slither-disable-next-line incorrect-equality -- triaged, security/triage.md T3
            if (edges.length == 0) _skipped(sp, SKIP_NO_EDGE);
            else markets[idx] = _open(sp);
            ++idx;
        }
        if (upDown) {
            Spec memory sp = Spec(token, dayId, idx, Kind.UPDOWN, new int64[](0), a.budgetUpDown);
            // An UP/DOWN market prices the move from the open, so it is never listed once the session has opened.
            if (block.timestamp >= _days[token][dayId].openTs) _skipped(sp, SKIP_AFTER_OPEN);
            else markets[idx] = _open(sp);
        }
    }

    function _anyOpened(address[] memory markets) internal pure returns (bool) {
        for (uint256 i; i < markets.length; ++i) {
            if (markets[i] != address(0)) return true;
        }
        return false;
    }

    function _open(Spec memory sp) internal returns (address m) {
        // slither-disable-next-line incorrect-equality -- triaged, security/triage.md T3
        uint8 n = sp.kind == Kind.RANGE ? uint8(sp.edges.length + 1) : 2;
        uint256 bWad = _bWad(sp.budget, n);
        // slither-disable-next-line incorrect-equality -- triaged, security/triage.md T3
        if (bWad == 0) {
            _skipped(sp, SKIP_BUDGET);
            return address(0);
        }
        bytes32 salt = _salt(sp.token, sp.dayId, sp.index);
        m = LibClone.predictDeterministicAddress(marketImpl, salt, address(this));
        isMarket[m] = true; // the pool may check isMarket during allocate
        try pool.allocate(m, sp.budget) {}
        catch (bytes memory err) {
            if (err.length == 0) revert AllocationFailed();
            isMarket[m] = false;
            _skipped(sp, SKIP_POOL_REFUSED);
            return address(0);
        }
        // slither-disable-next-line unused-return -- triaged, security/triage.md T4
        LibClone.cloneDeterministic(marketImpl, salt);
        ILMSRMarket(m).initialize(_config(sp, n, bWad), address(pool), address(oracle), address(router), staking);
    }

    function _config(Spec memory sp, uint8 n, uint256 bWad) internal view returns (ILMSRMarket.Config memory c) {
        DayInfo storage day = _days[sp.token][sp.dayId];
        c.token = sp.token;
        c.dayId = sp.dayId;
        c.kind = sp.kind;
        c.n = n;
        c.edges = sp.edges;
        c.createdTs = day.createdTs;
        c.openTs = day.openTs;
        c.haltTs = day.closeTs - Constants.HALT_BEFORE_CLOSE;
        c.closeTs = day.closeTs;
        c.multiplierSnapshot = day.multiplierSnapshot;
        c.bWad = bWad;
        c.budget = sp.budget;
        c.priorWad = _uniformPrior(n);
        c.baseFeeBps = _baseFeeBps;
        c.rampMaxBps = _rampMaxBps;
    }

    /// @dev Temporary uniform opening prices (Σ = 1e18); the dust goes to outcome 0.
    function _uniformPrior(uint8 n) internal pure returns (uint256[] memory p) {
        p = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            p[i] = 1e18 / n;
        }
        p[0] += 1e18 - (1e18 / n) * n;
    }

    /// @dev b = floor(budget × 1e18 / (lnWad(n) + 1)) base units, so b·ln n ≤ budget; returned in WAD (× 1e12).
    function _bWad(uint96 budget, uint8 n) internal pure returns (uint256) {
        uint256 lnN = uint256(FixedPointMathLib.lnWad(int256(uint256(n) * 1e18)));
        // slither-disable-next-line divide-before-multiply -- triaged, security/triage.md T2
        uint256 b = uint256(budget) * 1e18 / (lnN + 1);
        if (b < Constants.B_MIN || b > Constants.B_MAX) return 0;
        return b * 1e12;
    }

    function _skipped(Spec memory sp, uint8 reason) internal {
        emit MarketSkipped(sp.token, sp.dayId, uint8(sp.index), reason);
    }

    function _salt(address token, uint32 dayId, uint256 index) internal pure returns (bytes32) {
        return keccak256(abi.encode(token, dayId, index));
    }

    // ------------------------------------------------------------------ views

    function dayInfo(address token, uint32 dayId) external view returns (DayInfo memory) {
        return _days[token][dayId];
    }

    function marketsOf(address token, uint32 dayId) external view returns (address[] memory) {
        return _days[token][dayId].markets;
    }

    function predictMarket(address token, uint32 dayId, uint256 index) external view returns (address) {
        return LibClone.predictDeterministicAddress(marketImpl, _salt(token, dayId, index), address(this));
    }

    function template() external view returns (int16[] memory strikeBps, int16[] memory edgeBps, bool upDown) {
        return (_strikeBps, _edgeBps, _upDown);
    }

    // ------------------------------------------------------------------ roles

    function setTemplate(int16[] calldata strikeBps, int16[] calldata edgeBps, bool upDown) external onlyTimelock {
        _setTemplate(strikeBps, edgeBps, upDown);
    }

    function setListingBounty(uint96 amount) external onlyTimelock {
        if (amount > MAX_LISTING_BOUNTY) revert BountyTooHigh();
        listingBounty = amount;
        emit ListingBountySet(amount);
    }

    function setFees(uint16 baseFeeBps, uint16 rampMaxBps) external onlyTimelock {
        if (baseFeeBps > Constants.MAX_BASE_FEE_BPS || rampMaxBps > Constants.MAX_RAMP_BPS) revert BadFees();
        (_baseFeeBps, _rampMaxBps) = (baseFeeBps, rampMaxBps);
        emit FeesSet(baseFeeBps, rampMaxBps);
    }

    function fees() external view returns (uint16 baseFeeBps, uint16 rampMaxBps) {
        return (_baseFeeBps, _rampMaxBps);
    }

    function setListingPaused(bool paused) external onlyGuardian {
        listingPaused = paused;
        emit ListingPaused(paused);
    }

    function setSkip(address[] calldata tokens, uint32[] calldata dayIds, bool skip) external onlyGuardian {
        if (tokens.length != dayIds.length) revert LengthMismatch();
        for (uint256 i; i < tokens.length; ++i) {
            isSkipped[tokens[i]][dayIds[i]] = skip;
            emit SkipSet(tokens[i], dayIds[i], skip);
        }
    }

    function guardianVoid(address market, bytes32 reasonHash) external onlyGuardian {
        if (!isMarket[market]) revert UnknownMarket(market);
        if (block.timestamp >= ILMSRMarket(market).config().haltTs) revert PastHalt(market);
        ILMSRMarket(market).voidMarket(uint8(ISettlementOracle.VoidReason.GUARDIAN));
        emit GuardianVoided(market, reasonHash);
    }

    function _setTemplate(int16[] memory s, int16[] memory e, bool u) internal {
        if (s.length > MAX_STRIKES || e.length > MAX_EDGES) revert BadTemplate();
        if (s.length == 0 && e.length == 0 && !u) revert BadTemplate();
        _checkBps(s);
        _checkBps(e);
        _strikeBps = s;
        _edgeBps = e;
        _upDown = u;
        emit TemplateSet(s, e, u);
    }

    function _checkBps(int16[] memory a) internal pure {
        for (uint256 i; i < a.length; ++i) {
            if (a[i] <= -10_000 || a[i] >= 10_000) revert BadTemplate();
            if (i != 0 && a[i] <= a[i - 1]) revert BadTemplate();
        }
    }
}
