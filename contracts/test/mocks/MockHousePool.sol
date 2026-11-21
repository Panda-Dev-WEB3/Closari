// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

contract MockHousePool {
    error Refused();

    bool public refuseAll;
    bool public burnGas;
    bool public maturedQueuePending;
    uint256 public allocateCalls;
    mapping(address => bool) public refuseMarket;
    mapping(address => uint256) public allocated;

    function setRefuseAll(bool v) external {
        refuseAll = v;
    }

    function setBurnGas(bool v) external {
        burnGas = v;
    }

    function setRefuseMarket(address market, bool v) external {
        refuseMarket[market] = v;
    }

    function setMaturedQueuePending(bool v) external {
        maturedQueuePending = v;
    }

    function allocate(address market, uint256 budget) external {
        ++allocateCalls;
        if (burnGas) {
            while (true) {
                allocateCalls = allocateCalls + 1; // runs out of gas → empty revert data
            }
        }
        if (refuseAll || refuseMarket[market]) revert Refused();
        allocated[market] = budget;
    }
}
