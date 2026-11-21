// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ILMSRMarket} from "../../src/interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "../../src/interfaces/IMarketFactory.sol";

/// @notice Records what the factory configured; implements only what M1 calls.
contract MockMarket {
    error AlreadyInitialized();

    bool public initialized;
    address public pool;
    address public oracle;
    address public router;
    address public staking;
    uint8 public lastVoidReason;
    uint256 public voidCalls;

    address internal _token;
    uint32 internal _dayId;
    IMarketFactory.Kind internal _kind;
    uint8 internal _n;
    int64[] internal _edges;
    uint64 internal _createdTs;
    uint64 internal _openTs;
    uint64 internal _haltTs;
    uint64 internal _closeTs;
    uint256 internal _multiplierSnapshot;
    uint256 internal _bWad;
    uint96 internal _budget;
    uint256[] internal _priorWad;
    uint16 internal _baseFeeBps;
    uint16 internal _rampMaxBps;

    function initialize(
        ILMSRMarket.Config calldata c,
        address pool_,
        address oracle_,
        address router_,
        address staking_
    ) external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        (pool, oracle, router, staking) = (pool_, oracle_, router_, staking_);
        _token = c.token;
        _dayId = c.dayId;
        _kind = c.kind;
        _n = c.n;
        for (uint256 i; i < c.edges.length; ++i) {
            _edges.push(c.edges[i]);
        }
        _createdTs = c.createdTs;
        _openTs = c.openTs;
        _haltTs = c.haltTs;
        _closeTs = c.closeTs;
        _multiplierSnapshot = c.multiplierSnapshot;
        _bWad = c.bWad;
        _budget = c.budget;
        for (uint256 i; i < c.priorWad.length; ++i) {
            _priorWad.push(c.priorWad[i]);
        }
        _baseFeeBps = c.baseFeeBps;
        _rampMaxBps = c.rampMaxBps;
    }

    function config() external view returns (ILMSRMarket.Config memory c) {
        c.token = _token;
        c.dayId = _dayId;
        c.kind = _kind;
        c.n = _n;
        c.edges = _edges;
        c.createdTs = _createdTs;
        c.openTs = _openTs;
        c.haltTs = _haltTs;
        c.closeTs = _closeTs;
        c.multiplierSnapshot = _multiplierSnapshot;
        c.bWad = _bWad;
        c.budget = _budget;
        c.priorWad = _priorWad;
        c.baseFeeBps = _baseFeeBps;
        c.rampMaxBps = _rampMaxBps;
    }

    function voidMarket(uint8 reason) external {
        lastVoidReason = reason;
        ++voidCalls;
    }
}
