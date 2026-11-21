// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @notice discountBps with failure modes the market must survive.
contract MockStaking {
    enum Mode {
        Normal,
        Revert,
        BurnGas,
        Garbage
    }

    Mode public mode;
    mapping(address => uint16) public d;

    function set(address a, uint16 bps) external {
        d[a] = bps;
    }

    function setMode(Mode m) external {
        mode = m;
    }

    function discountBps(address a) external view returns (uint16) {
        if (mode == Mode.Revert) revert("nope");
        if (mode == Mode.BurnGas) {
            uint256 i;
            while (gasleft() > 100) {
                ++i;
            }
        }
        if (mode == Mode.Garbage) {
            assembly {
                mstore(0, 0xffffffffffff)
                return(0, 32)
            }
        }
        return d[a];
    }
}
