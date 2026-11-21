// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IMarketFactory} from "./IMarketFactory.sol";
import {ISignatureTransfer} from "permit2/ISignatureTransfer.sol";

/// @notice Fixed-b LMSR market over n in [2, 8] outcomes (Backend §3.4). Implemented in M2/M3.
interface ILMSRMarket {
    enum State {
        Trading,
        Resolved,
        Voided
    }

    struct Config {
        address token;
        uint32 dayId;
        IMarketFactory.Kind kind;
        uint8 n;
        int64[] edges; // token-terms price8, strictly increasing; ABOVE: 1, RANGE: n-1, UPDOWN: set by oracle
        uint64 createdTs;
        uint64 openTs;
        uint64 haltTs;
        uint64 closeTs;
        uint256 multiplierSnapshot;
        uint256 bWad;
        uint96 budget;
    }

    struct TradeIntent {
        address market;
        address owner;
        uint8 outcome;
        uint256 shares;
        uint256 maxTotal; // cost + fee ceiling, base units
        uint64 deadline;
        address builder;
        bytes32 salt;
    }

    event Trade(
        address indexed owner,
        uint8 indexed outcome,
        bool isBuy,
        uint256 shares,
        uint256 gross,
        uint256 fee,
        address indexed builder,
        uint256[] pricesWad
    );
    event Resolved(uint8 winner, int64 settlePrice8);
    event Voided(uint8 reason, uint256[] voidPricesWad);
    event Claimed(address indexed account, uint256 amount);
    event ClaimDeferred(address indexed account, uint256 amount);
    event Swept(uint256 toPool, uint256 feesToRouter);

    function initialize(Config calldata c, address pool, address oracle, address router, address staking) external;

    function config() external view returns (Config memory);
    function state() external view returns (State);

    function quoteBuy(uint8 outcome, uint256 shares, address account) external view returns (uint256 gross, uint256 fee);
    function quoteSell(uint8 outcome, uint256 shares, address account)
        external
        view
        returns (uint256 gross, uint256 fee);
    function prices() external view returns (uint256[] memory pWad);

    function buy(uint8 outcome, uint256 shares, uint256 maxTotal, uint64 deadline, address builder)
        external
        returns (uint256 total);
    function buyWithAuthorization(
        TradeIntent calldata t,
        uint256 validAfter,
        uint256 validBefore,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 total);
    function buyWithPermit2(
        TradeIntent calldata t,
        ISignatureTransfer.PermitTransferFrom calldata p,
        bytes calldata sig
    ) external returns (uint256 total);
    function sell(uint8 outcome, uint256 shares, uint256 minNet, uint64 deadline, address builder)
        external
        returns (uint256 net);

    function setOpenReference(int64 openPrice8, uint64 openConf8) external;
    function resolve(uint8 winner, int64 settlePrice8) external;
    function voidMarket(uint8 reason) external;

    function claim(address account) external returns (uint256 paid);
    function claimMany(address[] calldata accounts) external;
    function sweep() external;

    function shares(address account, uint8 outcome) external view returns (uint256);
    function liability() external view returns (uint256);
    function cash() external view returns (uint256);
}
