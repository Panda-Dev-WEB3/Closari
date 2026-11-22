// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @notice One close result per (token, dayId), one open result per UPDOWN (Backend §3.5). Implemented in M3.
interface ISettlementOracle {
    enum Tier {
        NONE,
        C,
        B,
        A
    }

    enum VoidReason {
        NONE,
        CONF_WIDE,
        DIVERGENCE,
        TIE_ZONE,
        CORP_ACTION,
        ORACLE_PAUSED,
        NO_PRICE,
        NO_OPEN,
        BAD_PRICE,
        GUARDIAN
    }

    error NotListed(address token, uint32 dayId);
    error TooEarly();
    error TooLate();
    error AlreadyFinal();
    error TierNotHigher();
    error WrongFeed(bytes32 got);
    error InsufficientFee(uint256 required);
    error NotFinal();
    error NoUpDownMarket();
    error BadOpen();
    error PhaseMismatch();
    error BadRound();
    error NotTimelock();
    error BountyTooHigh();

    struct PriceResult {
        int64 price8; // token terms
        uint64 conf8; // token terms
        uint64 publishTime;
        Tier tier;
        uint64 firstSubmitTs;
        bool final_;
        VoidReason dayVoid;
    }

    event CloseSubmitted(
        address indexed token, uint32 indexed dayId, Tier tier, int64 price8, uint64 conf8, uint64 publishTime
    );
    event CrossCheck(
        address indexed token,
        uint32 indexed dayId,
        uint80 roundId,
        int256 clAnswer,
        uint256 updatedAt,
        bool fresh,
        uint256 diffBps
    );
    event DayFinal(address indexed token, uint32 indexed dayId, int64 price8, VoidReason dayVoid);
    event OpenRecorded(address indexed token, uint32 indexed dayId, Tier tier, int64 price8, uint64 conf8);
    event OpenFinal(address indexed token, uint32 indexed dayId, int64 price8, VoidReason dayVoid);
    event BountiesSet(uint96 closeBounty, uint96 batchBounty, uint96 openBounty);

    function submitClose(address token, uint32 dayId, Tier tier, bytes[] calldata pythUpdate, uint80 clRoundId)
        external
        payable;
    function finalizeClose(address token, uint32 dayId) external;
    function voidExpired(address token, uint32 dayId) external;
    function settleMarkets(address token, uint32 dayId, uint256 from, uint256 to) external;
    function recordOpen(address token, uint32 dayId, Tier tier, bytes[] calldata pythUpdate) external payable;
    /// @notice Permissionless. Finalises a tier B/C open after IMPROVE_WINDOW and passes it to the UPDOWN market.
    function finalizeOpen(address token, uint32 dayId) external;
    function voidNoOpen(address token, uint32 dayId) external;

    /// @notice onlyTimelock. Each amount ≤ 5 USDG (5e6). Credited through the fee router, once per (action, token, day).
    function setBounties(uint96 closeBounty, uint96 batchBounty, uint96 openBounty) external;
    function bounties() external view returns (uint96 closeBounty, uint96 batchBounty, uint96 openBounty);

    function closeResult(address token, uint32 dayId) external view returns (PriceResult memory);
    function openResult(address token, uint32 dayId) external view returns (PriceResult memory);
}
