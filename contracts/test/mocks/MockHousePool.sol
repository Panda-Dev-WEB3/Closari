// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

contract MockHousePool {
    error Refused();

    bool public refuseAll;
    bool public burnGas;
    bool public maturedQueuePending;
    uint256 public allocateCalls;
    mapping(uint256 => bool) public refuseCall;
    mapping(address => uint256) public allocated;

    function setRefuseAll(bool v) external {
        refuseAll = v;
    }

    function setBurnGas(bool v) external {
        burnGas = v;
    }

    function setRefuseCall(uint256 callIndex, bool v) external {
        refuseCall[callIndex] = v;
    }

    function setMaturedQueuePending(bool v) external {
        maturedQueuePending = v;
    }

    function allocate(address market, uint256 budget) external {
        uint256 i = allocateCalls++;
        if (burnGas) {
            while (true) {
                allocateCalls = allocateCalls + 1; // runs out of gas → empty revert data
            }
        }
        if (refuseAll || refuseCall[i]) revert Refused();
        allocated[market] = budget;
    }
}
