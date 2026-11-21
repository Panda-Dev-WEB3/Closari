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

    error AlreadyInitialized();
    error BadConfig();
    error NotOracle();
    error NotYetImplemented();
    error NotTrading();
    error Halted();
    error Expired();
    error CorporateActionVisible();
    error AwaitingOpen();
    error OpenAlreadySet();
    error NotUpDown();
    error BadOutcome();
    error ZeroShares();
    error TradeTooLarge();
    error PriceOutOfBounds();
    error LateHourCap();
    error InsufficientShares();
    error Slippage();
    error WrongMarket();
    error WrongToken();
    error BadTimestamp();

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
        uint256[] priorWad; // opening prices, Σ = 1e18, each ≥ Constants.PRIOR_MIN (M2 spec §3)
        uint16 baseFeeBps; // snapshotted from the factory at listing
        uint16 rampMaxBps;
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
    /// @dev Under the pull model (Backend §3.8) sweep does not move fees: the router pulls them with pullFees.
    ///      feesToRouter reports fees already pulled by the router, which may be 0.
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
    /// @notice Sends the final market's surplus to the pool. Does not move fees (pull model); see Swept.
    function sweep() external;

    /// @notice Fees held by this market and not yet pulled by the router or refunded.
    function feeEscrow() external view returns (uint256);
    function feesPaid(address account) external view returns (uint256);
    function feesByBuilder(address builder) external view returns (uint256);
    /// @notice Sum of fees attributed to non-zero builders.
    function builderFeesTotal() external view returns (uint256);
    /// @notice Only the fee router, only when state == Resolved. Transfers feeEscrow to the router; a second call
    ///         returns 0 (Backend §3.8: distribute pulls feeEscrow from a resolved market).
    function pullFees() external returns (uint256 amount);

    function shares(address account, uint8 outcome) external view returns (uint256);
    function liability() external view returns (uint256);
    function cash() external view returns (uint256);
    /// @notice Cumulative floored price × seconds per outcome at `ts` (≥ the last trade time), n entries. The last
    ///         entry is implied: (ts − createdTs) × 1e18 − Σ others. Prices are constant between trades, so it is exact.
    function cumulativeAt(uint64 ts) external view returns (uint256[] memory cum);
    /// @notice Void-TWAP checkpoints. ts[0] = max(haltTs − 3600, createdTs); ts[1] = max(openTs − 3600, createdTs) for
    ///         UPDOWN, 0 otherwise. cum[j] has n entries (as cumulativeAt) and is empty when ts[j] == 0.
    function checkpoints() external view returns (uint64[2] memory ts, uint256[][2] memory cum);
}
