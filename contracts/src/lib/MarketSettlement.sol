// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ILMSRMarket} from "../interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "../interfaces/IMarketFactory.sol";
import {Constants} from "./Constants.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/// @notice Settlement maths for LMSRMarket (M3 spec §3). A linked library (public functions): its code lives once,
///         outside every market clone's bytecode budget, and no trade path calls it. Pure: the market passes in what
///         it reads from storage.
library MarketSettlement {
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

    /// @notice voidPrices and voidReserve in one call (keeps the market's bytecode small).
    function voidAll(uint256[] memory c0, uint256[] memory c1, uint256 w, uint256[] memory prior, uint256[] memory t)
        public
        pure
        returns (uint256[] memory v, uint256 reserve)
    {
        v = voidPrices(c0, c1, w, prior);
        reserve = voidReserve(t, v);
    }

    /// @notice One account's void payout before its fee refund: Σ_i floor(sh_i · v_i / 1e18).
    function voidOwed(uint256[] memory sh, uint256[] memory v) public pure returns (uint256 owed) {
        for (uint256 i; i < sh.length; ++i) {
            owed += FixedPointMathLib.mulDiv(sh[i], v[i], 1e18);
        }
    }

    /// @notice What a voided market keeps back for share claims: Σ_i ceil(t_i · v_i / 1e18) ≥ Σ_accounts voidOwed.
    function voidReserve(uint256[] memory t, uint256[] memory v) public pure returns (uint256 r) {
        for (uint256 i; i < t.length; ++i) {
            r += FixedPointMathLib.mulDivUp(t[i], v[i], 1e18);
        }
    }

    /// @notice Who may void, and when (M3 spec §4). GUARDIAN only from the factory before the halt; NO_OPEN only for an
    ///         UPDOWN market with no open, from openTs; every other reason only from the oracle at or after haltTs.
    function checkVoid(
        uint8 reason,
        address caller,
        address factory,
        address oracle,
        bool upDown,
        bool openRecorded,
        uint64 openTs,
        uint64 haltTs
    ) public view {
        if (reason == 9) {
            if (caller != factory) revert ILMSRMarket.NotFactory();
        } else if (caller != oracle) {
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
