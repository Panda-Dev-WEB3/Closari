// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @notice Immutable 80/10/5/5 fee split: pool / treasury / settler bounties / builder rebates (Backend §3.8).
interface IFeeRouter {
    event Distributed(
        address indexed market,
        uint256 total,
        uint256 toPool,
        uint256 toTreasury,
        uint256 toBounty,
        uint256 toBuilders,
        uint256 builderlessToPool
    );
    event BountyFunded(address indexed from, uint256 amount);

    function distribute(address market) external;
    function claimBuilder(address builder, address[] calldata markets) external;
    function creditBounty(address settler, uint256 amount) external;
    function claimBounty(address settler) external;
    /// @notice Anyone may fund. Pulls `amount` USDG from the caller into the bounty balance.
    function fundBounty(uint256 amount) external;
    function bountyBalance() external view returns (uint256);
    function treasury() external view returns (address);
}
