// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IHousePool} from "../interfaces/IHousePool.sol";
import {ILMSRMarket} from "../interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "../interfaces/IMarketFactory.sol";
import {Constants} from "./Constants.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @notice Settlement maths for LMSRMarket (M3 spec §3). A linked library (public functions): its code lives once,
///         outside every market clone's bytecode budget, and no trade path calls it. Pure: the market passes in what
///         it reads from storage.
interface IMarketFactoryOwner {
    function factory() external view returns (address);
    function oracle() external view returns (address);
    function pool() external view returns (address);
    function router() external view returns (address);
    function USDG() external view returns (address);
}

library MarketSettlement {
    using SafeTransferLib for address;

    /// @notice Every `initialize` check (M2 + the M3 deferred self-checks, M3 spec §8). Returns min_i priorWad[i].
    function validateConfig(ILMSRMarket.Config calldata c, address pool, address oracle)
        public
        pure
        returns (uint256 pMin)
    {
        uint256 n = c.n;
        if (
            c.token == address(0) || pool == address(0) || oracle == address(0) || n < 2 || n > 8
                || c.priorWad.length != n || c.bWad < Constants.B_MIN * 1e12 || c.bWad > Constants.B_MAX * 1e12
                || c.createdTs >= c.haltTs || c.haltTs >= c.closeTs || c.haltTs <= Constants.RAMP_WINDOW
                || c.baseFeeBps > Constants.MAX_BASE_FEE_BPS || c.rampMaxBps > Constants.MAX_RAMP_BPS
        ) revert ILMSRMarket.BadConfig();
        uint256 sum;
        pMin = type(uint256).max;
        for (uint256 i; i < n; ++i) {
            uint256 p = c.priorWad[i];
            if (p < Constants.PRIOR_MIN) revert ILMSRMarket.BadConfig();
            sum += p;
            if (p < pMin) pMin = p;
        }
        if (sum != 1e18) revert ILMSRMarket.BadConfig();
        // Loss bound (M2 spec §3): b · ln(1/p_min) ≤ budget, in base units (bWad = b · 1e12, ln in WAD).
        uint256 ln = uint256(FixedPointMathLib.lnWad(int256(FixedPointMathLib.divWad(1e18, pMin))));
        if (FixedPointMathLib.fullMulDiv(c.bWad, ln, 1e30) > c.budget) revert ILMSRMarket.BadConfig();
        _checkEdges(c, n);
    }

    /// @notice v_i = floor((c1_i − c0_i) / w), or the prior when w == 0 (M3 spec §5). Σ v ≤ 1e18 because
    ///         Σ (c1_i − c0_i) = w · 1e18 exactly (the last cumulative entry is implied) and each term is floored.
    function voidPrices(uint256[] memory c0, uint256[] memory c1, uint256 w, uint256[] memory prior)
        public
        pure
        returns (uint256[] memory v)
    {
        if (w == 0) return prior;
        v = new uint256[](c1.length);
        for (uint256 i; i < v.length; ++i) {
            v[i] = (c1[i] - c0[i]) / w;
        }
    }

    /// @notice Void prices and the reserve for the calling market (M3 spec §5). Runs by DELEGATECALL, so
    ///         address(this) is the market and its public views are read by self-call. Window: an UPDOWN market with no
    ///         open at or after openTs uses [checkpoint 1, openTs] whatever the reason; a guardian void uses
    ///         [createdTs, now] with c0 = 0; every other void uses [checkpoint 0, haltTs]. w == 0 gives the prior.
    function voidOutcome(bool guardian, uint256[] memory t) public view returns (uint256[] memory v, uint256 reserve) {
        ILMSRMarket m = ILMSRMarket(address(this));
        ILMSRMarket.Config memory c = m.config();
        uint256[] memory c0;
        uint256[] memory c1;
        uint256 w;
        if (c.kind == IMarketFactory.Kind.UPDOWN && c.edges.length == 0 && block.timestamp >= c.openTs) {
            (uint64[2] memory ts, uint256[][2] memory cp) = m.checkpoints();
            (c0, c1, w) = (cp[1], m.cumulativeAt(c.openTs), c.openTs - ts[1]);
        } else if (guardian) {
            c0 = new uint256[](c.n);
            (c1, w) = (m.cumulativeAt(uint64(block.timestamp)), block.timestamp - c.createdTs);
        } else {
            (uint64[2] memory ts, uint256[][2] memory cp) = m.checkpoints();
            (c0, c1, w) = (cp[0], m.cumulativeAt(c.haltTs), c.haltTs - ts[0]);
        }
        v = voidPrices(c0, c1, w, c.priorWad);
        reserve = voidReserve(t, v);
    }

    /// @notice Computes the void outcome for the calling market, writes the void prices into its storage array and
    ///         checks who may void and when, emits Voided (by DELEGATECALL, so the event comes from the market). Returns the reserve.
    function voidFinal(uint8 reason, uint256[8] storage x, uint256[8] storage x0, uint64[8] storage vs)
        public
        returns (uint256 reserve)
    {
        checkVoid(reason, msg.sender); // msg.sender is the market's caller under DELEGATECALL
        uint256 n = ILMSRMarket(address(this)).config().n;
        uint256[] memory t = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            t[i] = (x[i] - x0[i]) / 1e12;
        }
        uint256[] memory v;
        (v, reserve) = voidOutcome(reason == 9, t);
        for (uint256 i; i < v.length; ++i) {
            vs[i] = uint64(v[i]); // each ≤ 1e18 < 2^64
        }
        emit ILMSRMarket.Voided(reason, v);
    }

    /// @notice One account's void payout before its fee refund: Σ_i floor(sh_i · v_i / 1e18).
    function voidOwed(uint256[] memory sh, uint256[] memory v) public pure returns (uint256 owed) {
        for (uint256 i; i < sh.length; ++i) {
            owed += FixedPointMathLib.mulDiv(sh[i], v[i], 1e18);
        }
    }

    /// @notice Share payout and fee refund owed to `a` by the calling market (M3 spec §6), read by self-call under
    ///         DELEGATECALL. Resolved: the winning shares, no fee refund. Voided: Σ floor(sh_i · v_i / 1e18) plus the
    ///         fees `a` paid.
    function owedOf(address a) internal view returns (uint256 owed, uint256 fees) {
        ILMSRMarket m = ILMSRMarket(address(this));
        (uint8 winner,, uint256[] memory v) = m.finalInfo();
        if (v.length == 0) return (m.shares(a, winner), 0);
        uint256[] memory sh = new uint256[](v.length);
        for (uint256 i; i < sh.length; ++i) {
            sh[i] = m.shares(a, uint8(i));
        }
        return (voidOwed(sh, v), m.feesPaid(a));
    }

    /// @notice The sweep for the calling market, by DELEGATECALL: sends cash above the reserve to the pool (a refused
    ///         transfer reverts the whole sweep), reports the budget and the last worst/best cash to the pool, emits
    ///         Swept (M3 spec §7).
    function sweepFinal(uint256 feesPulled, uint256[8] storage x, uint256[8] storage x0) public {
        ILMSRMarket m = ILMSRMarket(address(this));
        if (m.state() == ILMSRMarket.State.Trading) revert ILMSRMarket.NotFinal();
        address pool = IMarketFactoryOwner(address(m)).pool();
        uint256 c = m.cash();
        uint256 reserve = m.liability(); // the reserve once final
        uint256 returned = c > reserve ? c - reserve : 0;
        uint256 hi;
        uint256 lo = type(uint256).max;
        for (uint256 i; i < m.config().n; ++i) {
            uint256 t = (x[i] - x0[i]) / 1e12;
            if (t > hi) hi = t;
            if (t < lo) lo = t;
        }
        if (returned != 0) IMarketFactoryOwner(address(m)).USDG().safeTransfer(pool, returned);
        IHousePool(pool).onSweep(m.config().budget, returned, c - hi, c - lo);
        emit ILMSRMarket.Swept(returned, feesPulled);
    }

    /// @notice Pays `a` what the calling market owes it, by DELEGATECALL, and marks it claimed. Returns the share payout
    ///         and the fee refund paid, or (0, 0) when nothing is owed, `a` already claimed, or the transfer was refused
    ///         (frozen account, paused token): then it emits ClaimDeferred and leaves `a` unclaimed, so one account never
    ///         blocks claimMany. USDG is a fixed, trusted token. The market moves its own totals.
    function claimFor(address a, mapping(address => bool) storage claimed)
        internal
        returns (uint256 owed, uint256 fees)
    {
        if (ILMSRMarket(address(this)).state() == ILMSRMarket.State.Trading) {
            revert ILMSRMarket.NotFinal();
        }
        if (claimed[a]) return (0, 0);
        (owed, fees) = owedOf(a);
        uint256 paid = owed + fees;
        if (paid == 0) return (0, 0);
        claimed[a] = true;
        (bool ok, bytes memory ret) =
            IMarketFactoryOwner(address(this)).USDG().call(abi.encodeWithSelector(0xa9059cbb, a, paid));
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) {
            claimed[a] = false;
            emit ILMSRMarket.ClaimDeferred(a, paid);
            return (0, 0);
        }
        emit ILMSRMarket.Claimed(a, paid);
    }

    /// @notice `claimFor` over a list; returns the totals paid.
    function claimBatch(address[] memory accounts, mapping(address => bool) storage claimed)
        public
        returns (uint256 owed, uint256 fees)
    {
        for (uint256 i; i < accounts.length; ++i) {
            (uint256 o, uint256 f) = claimFor(accounts[i], claimed);
            owed += o;
            fees += f;
        }
    }

    /// @notice What `a` could claim now: zero before final or once claimed.
    function claimableOf(address a, mapping(address => bool) storage claimed) public view returns (uint256) {
        if (ILMSRMarket(address(this)).state() == ILMSRMarket.State.Trading || claimed[a]) return 0;
        (uint256 owed, uint256 fees) = owedOf(a);
        return owed + fees;
    }

    /// @notice Sends the calling market's fee escrow to its router, by DELEGATECALL. Only the router, only when Resolved.
    ///         The market zeroes feeEscrow and counts the pull afterwards (the caller holds the reentrancy guard).
    function pullFeesTo() public returns (uint256 amount) {
        ILMSRMarket m = ILMSRMarket(address(this));
        address router = IMarketFactoryOwner(address(m)).router();
        if (msg.sender != router) revert ILMSRMarket.NotRouter();
        if (m.state() != ILMSRMarket.State.Resolved) revert ILMSRMarket.NotResolved();
        amount = m.feeEscrow();
        if (amount != 0) IMarketFactoryOwner(address(m)).USDG().safeTransfer(router, amount);
    }

    /// @notice What a voided market keeps back for share claims: Σ_i ceil(t_i · v_i / 1e18) ≥ Σ_accounts voidOwed.
    function voidReserve(uint256[] memory t, uint256[] memory v) public pure returns (uint256 r) {
        for (uint256 i; i < t.length; ++i) {
            r += FixedPointMathLib.mulDivUp(t[i], v[i], 1e18);
        }
    }

    /// @notice Who may void, and when (M3 spec §4). GUARDIAN only from the factory before the halt; NO_OPEN only for an
    ///         UPDOWN market with no open, from openTs; every other reason only from the oracle at or after haltTs.
    function checkVoid(uint8 reason, address caller) internal view {
        ILMSRMarket m = ILMSRMarket(address(this));
        ILMSRMarket.Config memory c = m.config();
        (uint64 openTs, uint64 haltTs) = (c.openTs, c.haltTs);
        bool upDown = c.kind == IMarketFactory.Kind.UPDOWN;
        bool openRecorded = c.edges.length != 0;
        if (reason == 9) {
            if (caller != IMarketFactoryOwner(address(m)).factory()) revert ILMSRMarket.NotFactory();
        } else if (caller != IMarketFactoryOwner(address(m)).oracle()) {
            revert ILMSRMarket.NotOracle();
        }
        if (reason == 9) {
            if (block.timestamp >= haltTs) revert ILMSRMarket.Halted();
        } else if (reason == 0 || reason > 9) {
            revert ILMSRMarket.BadReason();
        } else if (reason == 7) {
            if (!upDown || openRecorded) revert ILMSRMarket.BadReason();
            if (block.timestamp < openTs) revert ILMSRMarket.TooEarly();
        } else if (block.timestamp < haltTs) {
            revert ILMSRMarket.TooEarly();
        }
    }

    function _checkEdges(ILMSRMarket.Config calldata c, uint256 n) private pure {
        uint256 len = c.edges.length;
        if (c.kind == IMarketFactory.Kind.ABOVE) {
            if (n != 2 || len != 1) revert ILMSRMarket.BadConfig();
        } else if (c.kind == IMarketFactory.Kind.RANGE) {
            if (len != n - 1) revert ILMSRMarket.BadConfig();
        } else if (n != 2 || len != 0 || c.openTs <= c.createdTs || c.openTs >= c.haltTs) {
            revert ILMSRMarket.BadConfig();
        }
        for (uint256 i; i < len; ++i) {
            if (c.edges[i] <= 0 || (i != 0 && c.edges[i] <= c.edges[i - 1])) revert ILMSRMarket.BadConfig();
        }
    }
}
