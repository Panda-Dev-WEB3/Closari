// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @notice Lists the daily template markets for a stock token (Backend §3.3).
interface IMarketFactory {
    enum Kind {
        ABOVE,
        RANGE,
        UPDOWN
    }

    struct DayInfo {
        uint64 createdTs;
        uint64 openTs; // snapshotted from the calendar at listing; never re-read
        uint64 closeTs; // snapshotted from the calendar at listing; never re-read
        bytes32 pythId; // snapshotted from the allow-list at listing; never re-read
        address clFeed; // snapshotted from the allow-list at listing; never re-read
        uint256 multiplierSnapshot; // token.uiMultiplier() at listing, 1e18
        int64 refPrice8; // token-terms reference used for strikes
        address[] markets; // positional by template index; address(0) = not listed
    }

    /// @dev SKIP reasons for MarketSkipped.
    /// 1 = strike collapsed (duplicate or non-positive), 2 = budget gives b outside [1e3, 1e6] shares,
    /// 3 = pool refused the allocation, 4 = range template produced no edge,
    /// 5 = UPDOWN not listed at or after the session open (block.timestamp >= openTs).
    event DayListed(
        address indexed token, uint32 indexed dayId, int64 refPrice8, uint256 multiplier, address[] markets
    );
    event MarketSkipped(address indexed token, uint32 indexed dayId, uint8 index, uint8 reason);
    event ListingPaused(bool paused);
    event SkipSet(address indexed token, uint32 indexed dayId, bool skip);
    event TemplateSet(int16[] strikeBps, int16[] edgeBps, bool upDown);
    event ListingBountySet(uint96 amount);
    event FeesSet(uint16 baseFeeBps, uint16 rampMaxBps);
    event GuardianVoided(address indexed market, bytes32 reasonHash);

    error NotTimelock();
    error NotGuardian();
    error ListingIsPaused();
    error AlreadyListed(address token, uint32 dayId);
    error DaySkipped(address token, uint32 dayId);
    error AssetNotListed(address token);
    error NoSession(uint32 dayId);
    error TooLate(uint32 dayId);
    error TooEarly(uint32 dayId);
    error OraclePaused(address token);
    error CorporateActionPending(address token);
    error QueuePending();
    error PreviousDayNotFinal(address token, uint32 dayId);
    error ReferenceUpdateRequired();
    error InsufficientFee(uint256 required);
    error WrongFeed(bytes32 got);
    error BadReferencePrice();
    error ReferenceConfidenceTooWide();
    error BadTemplate();
    error LengthMismatch();
    error BountyTooHigh();
    error BadFees();
    error UnknownMarket(address market);
    error PastHalt(address market);
    /// @dev The pool reverted with empty data (out of gas or a bare revert). Listing reverts instead of skipping,
    ///      so a caller cannot starve pool.allocate of gas to drop markets. Pool refusals must use a custom error.
    error AllocationFailed();
    /// @dev Every template market was skipped. The whole listing reverts: no bounty, no snapshot, day stays listable.
    error NoMarketsOpened(address token, uint32 dayId);

    /// @notice Permissionless. Lists all template markets for (token, dayId). Excess msg.value is refunded.
    /// Requires: !listingPaused; asset listed & genuine; session exists; now < closeTs - 600 - 3600;
    /// now >= closeTs of the previous trading day (looked up within 10 days; no bound if none exists);
    /// not listed yet; not skipped; !oraclePaused(); no pending multiplier change with effectiveAt <= closeTs + 3600;
    /// pool has no matured unprocessed withdrawals; reference from the last final close within 3 trading days
    /// (rescaled by the current multiplier), else from refPythUpdate (publishTime within 120 s, conf/price <= 0.5%).
    /// Reverts NoMarketsOpened if every template market is skipped; no bounty is paid and the day stays listable.
    function listDay(address token, uint32 dayId, bytes[] calldata refPythUpdate)
        external
        payable
        returns (address[] memory markets);

    function dayInfo(address token, uint32 dayId) external view returns (DayInfo memory);
    function isMarket(address m) external view returns (bool);
    function marketsOf(address token, uint32 dayId) external view returns (address[] memory);
    function hasMarkets(uint32 dayId) external view returns (bool);
    function predictMarket(address token, uint32 dayId, uint256 index) external view returns (address);
    function template() external view returns (int16[] memory strikeBps, int16[] memory edgeBps, bool upDown);
    function listingBounty() external view returns (uint96);

    /// @notice onlyTimelock. Strictly increasing bps in (-10_000, 10_000). Max 8 ABOVE strikes, max 7 edges (8 buckets).
    function setTemplate(int16[] calldata strikeBps, int16[] calldata edgeBps, bool upDown) external;
    /// @notice onlyTimelock. Fee parameters copied into each market's Config at listing. base ≤ 200, rampMax ≤ 500 bps.
    function setFees(uint16 baseFeeBps, uint16 rampMaxBps) external;
    function fees() external view returns (uint16 baseFeeBps, uint16 rampMaxBps);
    /// @notice onlyTimelock. Capped at 5 USDG.
    function setListingBounty(uint96 amount) external;
    /// @notice onlyGuardian. Stops NEW listings only.
    function setListingPaused(bool paused) external;
    /// @notice onlyGuardian. Per (token, dayId) listing skip; tokens[i] pairs with dayIds[i].
    function setSkip(address[] calldata tokens, uint32[] calldata dayIds, bool skip) external;
    /// @notice onlyGuardian. Voids a market before its haltTs only (unscheduled closure).
    function guardianVoid(address market, bytes32 reasonHash) external;
}
