// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC20} from "solady/tokens/ERC20.sol";

/// @notice 6-decimal stable with the issuer controls Closari must tolerate: per-account freeze and global pause.
contract MockUSDG is ERC20 {
    error Frozen(address account);
    error Paused();

    bool public paused;
    mapping(address => bool) public frozen;

    function name() public pure override returns (string memory) {
        return "Mock USDG";
    }

    function symbol() public pure override returns (string memory) {
        return "USDG";
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setFrozen(address account, bool v) external {
        frozen[account] = v;
    }

    function setPaused(bool v) external {
        paused = v;
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        if (paused) revert Paused();
        if (frozen[from]) revert Frozen(from);
        if (frozen[to]) revert Frozen(to);
    }
}
