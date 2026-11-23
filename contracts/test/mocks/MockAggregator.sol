// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

contract MockAggregator {
    uint8 public immutable decimals;
    string public description;
    uint80 internal _latest;
    mapping(uint80 => int256) internal _answer;
    mapping(uint80 => uint256) internal _updatedAt;

    constructor(uint8 decimals_, string memory description_) {
        decimals = decimals_;
        description = description_;
    }

    function setRound(uint80 roundId, int256 answer, uint256 updatedAt) external {
        _answer[roundId] = answer;
        _updatedAt[roundId] = updatedAt;
        if (roundId > _latest) _latest = roundId;
    }

    bool public revertOnMissing;

    function setRevertOnMissing(bool v) external {
        revertOnMissing = v;
    }

    function getRoundData(uint80 roundId) public view returns (uint80, int256, uint256, uint256, uint80) {
        require(!revertOnMissing || _updatedAt[roundId] != 0, "No data present");
        return (roundId, _answer[roundId], _updatedAt[roundId], _updatedAt[roundId], roundId);
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return getRoundData(_latest);
    }
}
