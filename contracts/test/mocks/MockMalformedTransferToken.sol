// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @notice Runtime code to etch over a token address: every call succeeds but returns malformed data. The mode is read
///         from storage slot 0 of the etched address (set it with `vm.store`): 1 returns one byte (0x01), 2 returns a
///         full word holding 2, 3 returns a full word holding 0, anything else returns nothing.
contract MockMalformedTransferToken {
    fallback() external {
        assembly {
            let mode := sload(0)
            if eq(mode, 1) {
                mstore(0, shl(248, 1))
                return(0, 1)
            }
            if eq(mode, 2) {
                mstore(0, 2)
                return(0, 32)
            }
            if eq(mode, 3) {
                mstore(0, 0)
                return(0, 32)
            }
            return(0, 0)
        }
    }
}
