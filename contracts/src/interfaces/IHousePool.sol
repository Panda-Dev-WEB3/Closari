// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @notice The single USDG house pool that funds every market's budget (Backend §3.7). Implemented in M7.
interface IHousePool {
    event Deposit(address indexed from, address indexed receiver, uint256 assets, uint256 shares);
    event WithdrawInstant(
        address indexed owner, address indexed receiver, uint256 shares, uint256 assets, uint256 exitFee
    );
    event WithdrawQueued(uint256 indexed id, address indexed owner, uint256 shares);
    event WithdrawProcessed(uint256 indexed id, uint256 assets);
    event Allocated(address indexed market, uint256 budget);
    event Swept(address indexed market, uint256 budget, uint256 returned);

    function deposit(uint256 assets, address receiver, uint256 minShares) external returns (uint256 shares);
    function depositWithAuthorization(
        address from,
        uint256 assets,
        address receiver,
        uint256 minShares,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 salt,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256);
    function withdrawInstant(uint256 shares, address receiver, uint256 minAssets) external returns (uint256 assets);
    function requestWithdraw(uint256 shares, address receiver) external returns (uint256 id);
    function processQueue(uint256 maxItems) external;

    function allocate(address market, uint256 budget) external;
    function onMark(int256 dWorst, int256 dBest) external;
    function onSweep(uint256 budget, uint256 returned, uint256 lastWorst, uint256 lastBest) external;
    function addFees(uint256 amount) external;

    function freeCash() external view returns (uint256);
    function reserved() external view returns (uint256);
    function queuedAssetsEstimate() external view returns (uint256);
    function navInstant() external view returns (uint256);
    function navDeposit() external view returns (uint256);
    /// @notice True while a withdrawal request older than the previous close is unprocessed (listing blocks on it).
    function maturedQueuePending() external view returns (bool);
}
