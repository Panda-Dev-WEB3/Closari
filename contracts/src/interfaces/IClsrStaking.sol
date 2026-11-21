// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @notice $CLSR staking for base-fee discounts only; holds tokens, receives no fees (Backend §3.9).
interface IClsrStaking {
    event Staked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount);

    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function matureOf(address account) external view returns (uint256);
    function discountBps(address account) external view returns (uint16);
    function tiers() external view returns (uint256[3] memory thresholds);
}
