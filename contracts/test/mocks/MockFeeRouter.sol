// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

contract MockFeeRouter {
    uint256 public creditCalls;
    mapping(address => uint256) public bounties;

    function creditBounty(address settler, uint256 amount) external {
        ++creditCalls;
        bounties[settler] += amount;
    }
}
