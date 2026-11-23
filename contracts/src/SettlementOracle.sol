// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IFeeRouter} from "./interfaces/IFeeRouter.sol";
import {ILMSRMarket} from "./interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "./interfaces/IMarketFactory.sol";
import {ISettlementOracle} from "./interfaces/ISettlementOracle.sol";
import {IStockToken} from "./interfaces/external/IStockToken.sol";
import {Constants} from "./lib/Constants.sol";
import {PriceMath} from "./lib/PriceMath.sol";
import {AggregatorV3Interface} from "@chainlink/AggregatorV3Interface.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @notice One close result per (token, dayId) and one open per UPDOWN market (Backend §3.5, M3 spec §9). Every
///         input that decides a result comes from the factory's listing snapshot (I17), never from the caller.
contract SettlementOracle is ISettlementOracle, ReentrancyGuardTransient {
    uint256 public constant CONF_MAX_BPS = 50;
    uint64 public constant CL_FRESH = 900;
    uint256 public constant CL_DIVERGE_BPS = 100;
    uint64 public constant SETTLE_WINDOW = 7_200;
    uint64 public constant IMPROVE_WINDOW = 1_800;
    uint64 public constant OPEN_WINDOW = 7_200;
    uint96 public constant MAX_BOUNTY = 5e6;

    IPyth public immutable pyth;
    IMarketFactory public immutable factory;
    IFeeRouter public immutable router;
    address public immutable timelock;

    struct Close {
        PriceResult r;
        address submitter; // of the stored result: the close bounty goes here when it becomes final
        VoidReason frozen; // CORP_ACTION or ORACLE_PAUSED, fixed at the first submission
        bool checked; // first-submission checks done
        bool clFresh; // a usable Chainlink round, fresh at the bell
        bool batchPaid;
        int256 cl8; // that round's answer: token terms, 8 decimals, never multiplied
    }

    struct Open {
        PriceResult r;
        address submitter;
    }

    struct Px {
        int64 p; // token terms
        uint64 c; // token terms
        uint64 pt;
        VoidReason v; // BAD_PRICE or CONF_WIDE, else NONE
        uint256 fee;
    }

    mapping(address => mapping(uint32 => Close)) internal _close;
    mapping(address => mapping(uint32 => Open)) internal _open;
    uint96 internal _closeBounty;
    uint96 internal _batchBounty;
    uint96 internal _openBounty;

    constructor(address pyth_, address factory_, address router_, address timelock_) {
        pyth = IPyth(pyth_);
        factory = IMarketFactory(factory_);
        router = IFeeRouter(router_);
        timelock = timelock_;
    }

    function _useTransientReentrancyGuardOnlyOnMainnet() internal pure override returns (bool) {
        return false; // 4663 supports TSTORE
    }

    // ------------------------------------------------------------------ admin and views

    function setBounties(uint96 closeBounty, uint96 batchBounty, uint96 openBounty) external {
        if (msg.sender != timelock) revert NotTimelock();
        if (closeBounty > MAX_BOUNTY || batchBounty > MAX_BOUNTY || openBounty > MAX_BOUNTY) revert BountyTooHigh();
        (_closeBounty, _batchBounty, _openBounty) = (closeBounty, batchBounty, openBounty);
        emit BountiesSet(closeBounty, batchBounty, openBounty);
    }

    function bounties() external view returns (uint96, uint96, uint96) {
        return (_closeBounty, _batchBounty, _openBounty);
    }

    function closeResult(address token, uint32 dayId) external view returns (PriceResult memory) {
        return _close[token][dayId].r;
    }

    function openResult(address token, uint32 dayId) external view returns (PriceResult memory) {
        return _open[token][dayId].r;
    }

    // ------------------------------------------------------------------ close

    // slither-disable-next-line reentrancy-eth -- triaged, security/triage.md T6
    function submitClose(address token, uint32 dayId, Tier tier, bytes[] calldata pythUpdate, uint80 clRoundId)
        external
        payable
        nonReentrant
    {
        IMarketFactory.DayInfo memory d = _day(token, dayId);
        Close storage s = _close[token][dayId];
        _checkSubmit(s.r, tier, d.closeTs, SETTLE_WINDOW);
        Px memory x = _price(d, pythUpdate, d.closeTs - _width(tier), d.closeTs);
        if (!s.checked) {
            s.checked = true;
            s.frozen = _corporateAction(token, d);
            _crossCheck(s, token, dayId, d, clRoundId, x.p);
        }
        if (x.v == VoidReason.NONE && s.clFresh && _diverges(s.cl8, x.p)) x.v = VoidReason.DIVERGENCE;
        if (s.frozen != VoidReason.NONE) x.v = s.frozen;
        _store(s.r, x, tier);
        s.submitter = msg.sender;
        emit CloseSubmitted(token, dayId, tier, x.p, x.c, x.pt);
        if (tier == Tier.A) _finalClose(token, dayId, s);
        _refund(x.fee);
    }

    function finalizeClose(address token, uint32 dayId) external nonReentrant {
        _day(token, dayId);
        Close storage s = _close[token][dayId];
        if (s.r.final_) revert AlreadyFinal();
        if (s.r.tier == Tier.NONE || block.timestamp < s.r.firstSubmitTs + IMPROVE_WINDOW) revert TooEarly();
        _finalClose(token, dayId, s);
    }

    function voidExpired(address token, uint32 dayId) external nonReentrant {
        IMarketFactory.DayInfo memory d = _day(token, dayId);
        Close storage s = _close[token][dayId];
        if (s.r.final_) revert AlreadyFinal();
        if (s.r.tier != Tier.NONE || block.timestamp <= d.closeTs + SETTLE_WINDOW) revert TooEarly();
        s.r.dayVoid = VoidReason.NO_PRICE;
        _finalClose(token, dayId, s); // no submitter: no close bounty
    }

    // ------------------------------------------------------------------ open (UPDOWN)

    // slither-disable-next-line reentrancy-eth -- triaged, security/triage.md T6
    function recordOpen(address token, uint32 dayId, Tier tier, bytes[] calldata pythUpdate)
        external
        payable
        nonReentrant
    {
        IMarketFactory.DayInfo memory d = _day(token, dayId);
        ILMSRMarket m = _upDown(d);
        Open storage o = _open[token][dayId];
        _checkSubmit(o.r, tier, d.openTs, OPEN_WINDOW);
        Px memory x = _price(d, pythUpdate, d.openTs, d.openTs + _width(tier));
        if (x.v != VoidReason.NONE) revert BadOpen(); // the open stays unset: a higher tier can still land
        _store(o.r, x, tier);
        o.submitter = msg.sender;
        emit OpenRecorded(token, dayId, tier, x.p, x.c);
        if (tier == Tier.A) _finalOpen(token, dayId, o, m);
        _refund(x.fee);
    }

    function finalizeOpen(address token, uint32 dayId) external nonReentrant {
        ILMSRMarket m = _upDown(_day(token, dayId));
        Open storage o = _open[token][dayId];
        if (o.r.final_) revert AlreadyFinal();
        if (o.r.tier == Tier.NONE || block.timestamp < o.r.firstSubmitTs + IMPROVE_WINDOW) revert TooEarly();
        _finalOpen(token, dayId, o, m);
    }

    function voidNoOpen(address token, uint32 dayId) external nonReentrant {
        IMarketFactory.DayInfo memory d = _day(token, dayId);
        ILMSRMarket m = _upDown(d);
        Open storage o = _open[token][dayId];
        if (o.r.final_) revert AlreadyFinal();
        if (o.r.tier != Tier.NONE || block.timestamp <= d.openTs + OPEN_WINDOW) revert TooEarly();
        _noOpen(token, dayId, o);
        if (m.state() == ILMSRMarket.State.Trading) m.voidMarket(uint8(VoidReason.NO_OPEN));
    }

    // ------------------------------------------------------------------ settlement

    // slither-disable-next-line reentrancy-no-eth -- triaged, security/triage.md T7
    function settleMarkets(address token, uint32 dayId, uint256 from, uint256 to) external nonReentrant {
        IMarketFactory.DayInfo memory d = _day(token, dayId);
        Close storage s = _close[token][dayId];
        if (!s.r.final_) revert NotFinal();
        PriceResult memory r = s.r;
        if (to > d.markets.length) to = d.markets.length;
        // slither-disable-next-line uninitialized-local -- triaged, security/triage.md T8
        uint256 settled;
        for (uint256 i = from; i < to; ++i) {
            ILMSRMarket m = ILMSRMarket(d.markets[i]);
            // M1 obligation 2: skip empty slots and markets already final (e.g. after guardianVoid).
            if (address(m) == address(0) || m.state() != ILMSRMarket.State.Trading) continue;
            _settle(token, dayId, d, m, r);
            ++settled;
        }
        if (settled != 0 && !s.batchPaid) {
            s.batchPaid = true;
            _credit(msg.sender, _batchBounty);
        }
    }

    function _settle(address token, uint32 dayId, IMarketFactory.DayInfo memory d, ILMSRMarket m, PriceResult memory r)
        internal
    {
        ILMSRMarket.Config memory c = m.config();
        bool upDown = c.kind == IMarketFactory.Kind.UPDOWN;
        // slither-disable-next-line uninitialized-local -- triaged, security/triage.md T8
        PriceResult memory o;
        if (upDown) o = _syncOpen(token, dayId, d, m);
        if (r.dayVoid != VoidReason.NONE) {
            m.voidMarket(uint8(r.dayVoid));
            return;
        }
        int256 s = r.price8;
        if (upDown) {
            if (!o.final_ || o.dayVoid != VoidReason.NONE) {
                m.voidMarket(uint8(VoidReason.NO_OPEN));
            } else if (_absDiff(s, o.price8) <= uint256(r.conf8) + o.conf8) {
                m.voidMarket(uint8(VoidReason.TIE_ZONE));
            } else {
                m.resolve(s > o.price8 ? 1 : 0, r.price8);
            }
            return;
        }
        // slither-disable-next-line uninitialized-local -- triaged, security/triage.md T8
        uint8 w; // ABOVE: 1 if S > K; RANGE: the number of edges ≤ S (bucket index)
        for (uint256 j; j < c.edges.length; ++j) {
            if (_absDiff(s, c.edges[j]) <= r.conf8) {
                m.voidMarket(uint8(VoidReason.TIE_ZONE));
                return;
            }
            if (c.edges[j] < s) ++w;
        }
        m.resolve(w, r.price8);
    }

    /// @dev Brings the open up to date before settling an UPDOWN market (a missed finalizeOpen or voidNoOpen).
    function _syncOpen(address token, uint32 dayId, IMarketFactory.DayInfo memory d, ILMSRMarket m)
        internal
        returns (PriceResult memory)
    {
        Open storage o = _open[token][dayId];
        if (!o.r.final_) {
            if (o.r.tier != Tier.NONE) {
                if (block.timestamp >= o.r.firstSubmitTs + IMPROVE_WINDOW) _finalOpen(token, dayId, o, m);
            } else if (block.timestamp > d.openTs + OPEN_WINDOW) {
                _noOpen(token, dayId, o);
            }
        }
        return o.r;
    }

    // ------------------------------------------------------------------ internals

    function _day(address token, uint32 dayId) internal view returns (IMarketFactory.DayInfo memory d) {
        d = factory.dayInfo(token, dayId);
        if (d.createdTs == 0) revert NotListed(token, dayId);
    }

    /// @dev The factory always places the UPDOWN market last.
    function _upDown(IMarketFactory.DayInfo memory d) internal view returns (ILMSRMarket m) {
        uint256 len = d.markets.length;
        if (len != 0) m = ILMSRMarket(d.markets[len - 1]);
        if (address(m) == address(0) || m.config().kind != IMarketFactory.Kind.UPDOWN) revert NoUpDownMarket();
    }

    function _checkSubmit(PriceResult storage r, Tier tier, uint64 anchor, uint64 window) internal view {
        if (block.timestamp < anchor) revert TooEarly();
        if (r.final_) revert AlreadyFinal();
        if (r.tier == Tier.NONE) {
            if (block.timestamp > anchor + window) revert TooLate();
        } else if (block.timestamp >= r.firstSubmitTs + IMPROVE_WINDOW) {
            revert TooLate();
        }
        if (uint8(tier) <= uint8(r.tier)) revert TierNotHigher(); // NONE never passes
    }

    /// @dev Tier width in seconds: A 0, B 5, C 60.
    function _width(Tier tier) internal pure returns (uint64) {
        if (tier == Tier.A) return 0;
        return tier == Tier.B ? 5 : 60;
    }

    /// @dev Parses the first update in [lo, hi] for the snapshotted feed (Unique parse), checks price and confidence
    ///      in share terms, then converts to token terms once (I11).
    function _price(IMarketFactory.DayInfo memory d, bytes[] calldata upd, uint64 lo, uint64 hi)
        internal
        returns (Px memory x)
    {
        x.fee = pyth.getUpdateFee(upd);
        if (msg.value < x.fee) revert InsufficientFee(x.fee);
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = d.pythId;
        PythStructs.PriceFeed[] memory f = pyth.parsePriceFeedUpdatesUnique{value: x.fee}(upd, ids, lo, hi);
        if (f[0].id != d.pythId) revert WrongFeed(f[0].id);
        (int256 p8, uint256 c8) = PriceMath.to8(f[0].price.price, f[0].price.conf, f[0].price.expo);
        if (p8 <= 0) x.v = VoidReason.BAD_PRICE;
        else if (c8 * 10_000 > uint256(p8) * CONF_MAX_BPS) x.v = VoidReason.CONF_WIDE;
        x.p = SafeCastLib.toInt64(PriceMath.toTokenTerms(p8, d.multiplierSnapshot));
        x.c = SafeCastLib.toUint64(PriceMath.toTokenTermsConf(c8, d.multiplierSnapshot));
        x.pt = uint64(f[0].price.publishTime);
    }

    function _store(PriceResult storage r, Px memory x, Tier tier) internal {
        (r.price8, r.conf8, r.publishTime, r.tier, r.dayVoid) = (x.p, x.c, x.pt, tier, x.v);
        if (r.firstSubmitTs == 0) r.firstSubmitTs = uint64(block.timestamp);
    }

    /// @dev Backend §3.5 step 7, evaluated once, at the first submission.
    function _corporateAction(address token, IMarketFactory.DayInfo memory d) internal view returns (VoidReason) {
        IStockToken t = IStockToken(token);
        uint256 snap = d.multiplierSnapshot;
        if (t.uiMultiplier() != snap) return VoidReason.CORP_ACTION;
        if (t.newUIMultiplier() != snap) {
            uint256 at = t.effectiveAt();
            if (at >= d.createdTs && at <= uint256(d.closeTs) + Constants.CA_AFTER) return VoidReason.CORP_ACTION;
        }
        if (t.oraclePaused()) return VoidReason.ORACLE_PAUSED;
        return VoidReason.NONE;
    }

    function _crossCheck(
        Close storage s,
        address token,
        uint32 dayId,
        IMarketFactory.DayInfo memory d,
        uint80 rid,
        int64 p
    ) internal {
        (bool ok, bool fresh, int256 answer, uint256 updatedAt, uint80 used) = _locate(d.clFeed, rid, d.closeTs);
        s.clFresh = ok && fresh;
        s.cl8 = answer;
        uint256 diff = ok && p > 0 ? _absDiff(answer, p) * 10_000 / uint256(int256(p)) : 0;
        emit CrossCheck(token, dayId, used, answer, updatedAt, ok && fresh, diff);
    }

    /// @dev Phase-safe round location (ISettlementOracle.submitClose natspec). Reverts PhaseMismatch for a round outside
    ///      the current phase and BadRound for any round that is not the last one at or before the bell, so a caller
    ///      can never dodge the cross-check. `ok` is false only when the cross-check is unavailable.
    function _locate(address feed, uint80 rid, uint64 closeTs)
        internal
        view
        returns (bool ok, bool fresh, int256 answer, uint256 updatedAt, uint80 used)
    {
        AggregatorV3Interface agg = AggregatorV3Interface(feed);
        // slither-disable-next-line unused-return -- triaged, security/triage.md T9
        (uint80 latest,,,,) = agg.latestRoundData();
        uint80 phase = latest >> 64;
        if (rid == 0) {
            // slither-disable-next-line unused-return -- triaged, security/triage.md T9
            (,,, uint256 first,) = agg.getRoundData((phase << 64) | 1);
            if (first <= closeTs) revert BadRound();
            return (false, false, 0, 0, 0);
        }
        if (rid >> 64 != phase) revert PhaseMismatch();
        // slither-disable-next-line unused-return -- triaged, security/triage.md T9
        (, answer,, updatedAt,) = agg.getRoundData(rid);
        if (updatedAt == 0 || updatedAt > closeTs) revert BadRound();
        // slither-disable-next-line unused-return -- triaged, security/triage.md T9
        try agg.getRoundData(rid + 1) returns (uint80, int256, uint256, uint256 nextAt, uint80) {
            if (nextAt != 0 && nextAt <= closeTs) revert BadRound();
        } catch {}
        used = rid;
        ok = answer > 0;
        fresh = closeTs - updatedAt <= CL_FRESH;
    }

    function _diverges(int256 cl, int64 p) internal pure returns (bool) {
        return p > 0 && _absDiff(cl, p) * 10_000 > uint256(int256(p)) * CL_DIVERGE_BPS;
    }

    function _absDiff(int256 a, int256 b) internal pure returns (uint256) {
        return a > b ? uint256(a - b) : uint256(b - a);
    }

    function _finalClose(address token, uint32 dayId, Close storage s) internal {
        s.r.final_ = true; // I8: never written again
        emit DayFinal(token, dayId, s.r.price8, s.r.dayVoid);
        _credit(s.submitter, _closeBounty);
    }

    /// @dev Passes the open to the market only while it trades and before its halt (M3 spec §9.4); after the halt
    ///      settlement uses the oracle's open directly and a void uses the window ending at openTs.
    function _finalOpen(address token, uint32 dayId, Open storage o, ILMSRMarket m) internal {
        o.r.final_ = true;
        if (m.state() == ILMSRMarket.State.Trading && block.timestamp < m.config().haltTs) {
            m.setOpenReference(o.r.price8, o.r.conf8);
        }
        _credit(o.submitter, _openBounty);
        emit OpenFinal(token, dayId, o.r.price8, VoidReason.NONE);
    }

    function _noOpen(address token, uint32 dayId, Open storage o) internal {
        o.r.final_ = true;
        o.r.dayVoid = VoidReason.NO_OPEN;
        emit OpenFinal(token, dayId, 0, VoidReason.NO_OPEN);
    }

    /// @dev The router must never revert here (M1 obligation 4).
    function _credit(address to, uint96 amount) internal {
        if (amount != 0 && to != address(0)) router.creditBounty(to, amount);
    }

    function _refund(uint256 fee) internal {
        if (msg.value > fee) SafeTransferLib.safeTransferETH(msg.sender, msg.value - fee);
    }
}
