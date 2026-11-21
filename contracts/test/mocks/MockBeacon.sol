// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

contract MockBeacon {
    address internal _impl;
    bool public reverts;

    constructor(address impl) {
        _impl = impl;
    }

    function setImplementation(address impl) external {
        _impl = impl;
    }

    function setReverts(bool v) external {
        reverts = v;
    }

    function implementation() external view returns (address) {
        require(!reverts, "beacon down");
        return _impl;
    }
}

/// @notice Returns 31 bytes of return data: shorter than an ABI word.
contract MockBeaconShortReturn {
    function implementation() external pure returns (address) {
        assembly {
            return(0, 31)
        }
    }
}

/// @notice Returns a full word with bits set above the address range: a dirty address.
contract MockBeaconDirtyReturn {
    function implementation() external pure returns (address) {
        assembly {
            mstore(0, not(0))
            return(0, 32)
        }
    }
}

/// @notice Never returns; burns whatever gas it is given.
contract MockBeaconBurnsGas {
    function implementation() external pure returns (address) {
        while (true) {}
        return address(0);
    }
}

/// @notice Spends about 120k gas before answering: a costlier issuer beacon that must still be accepted.
contract MockBeaconCostly {
    address internal immutable _impl;

    constructor(address impl) {
        _impl = impl;
    }

    function implementation() external view returns (address) {
        uint256 start = gasleft();
        while (start - gasleft() < 120_000) {}
        return _impl;
    }
}
