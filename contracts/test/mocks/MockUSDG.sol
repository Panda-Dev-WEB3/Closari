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

    error CallerMustBePayee();
    error AuthorizationNotYetValid();
    error AuthorizationExpired();
    error AuthorizationUsed();
    error InvalidSignature();

    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    mapping(address => mapping(bytes32 => bool)) public authorizationState;

    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (msg.sender != to) revert CallerMustBePayee();
        if (block.timestamp <= validAfter) revert AuthorizationNotYetValid();
        if (block.timestamp >= validBefore) revert AuthorizationExpired();
        if (authorizationState[from][nonce]) revert AuthorizationUsed();
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
                )
            )
        );
        address signer = ecrecover(digest, v, r, s);
        if (signer == address(0) || signer != from) revert InvalidSignature();
        authorizationState[from][nonce] = true;
        _transfer(from, to, value);
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
