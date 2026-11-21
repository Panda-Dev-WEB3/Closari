// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LMSRMarket} from "../src/LMSRMarket.sol";
import {ILMSRMarket} from "../src/interfaces/ILMSRMarket.sol";
import {IMarketFactory} from "../src/interfaces/IMarketFactory.sol";
import {MockUSDG} from "./mocks/MockUSDG.sol";
import {MarketFixture} from "./utils/MarketFixture.sol";
import {IEIP712} from "permit2/IEIP712.sol";
import {ISignatureTransfer} from "permit2/ISignatureTransfer.sol";

contract LMSRMarketSignedTest is MarketFixture {
    bytes32 constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    LMSRMarket m;
    uint256 ownerPk = 0xA11CE;
    address owner;
    address relayer = makeAddr("relayer");

    function setUp() public override {
        super.setUp();
        vm.etch(PERMIT2, vm.parseBytes(vm.readFile("test/fixtures/permit2.runtime.hex")));
        m = _market(IMarketFactory.Kind.ABOVE, _uniform(2), BUDGET);
        owner = vm.addr(ownerPk);
        usdg.mint(owner, 10_000e6);
    }

    function _intent(uint256 maxTotal) internal view returns (ILMSRMarket.TradeIntent memory t) {
        t = ILMSRMarket.TradeIntent({
            market: address(m),
            owner: owner,
            outcome: 1,
            shares: 100e6,
            maxTotal: maxTotal,
            deadline: uint64(block.timestamp + 600),
            builder: builder,
            salt: bytes32(uint256(7))
        });
    }

    function _hash(ILMSRMarket.TradeIntent memory t) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                m.TRADE_TYPEHASH(), t.market, t.owner, t.outcome, t.shares, t.maxTotal, t.deadline, t.builder, t.salt
            )
        );
    }

    function _sign3009(ILMSRMarket.TradeIntent memory t) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                usdg.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(),
                t.owner,
                address(m),
                t.maxTotal,
                block.timestamp - 1,
                block.timestamp + 600,
                _hash(t)
            )
        );
        return vm.sign(ownerPk, keccak256(abi.encodePacked("\x19\x01", usdg.DOMAIN_SEPARATOR(), structHash)));
    }

    function test_3009_creditsOwner_refundsExcess() public {
        ILMSRMarket.TradeIntent memory t = _intent(80e6);
        (uint8 v, bytes32 r, bytes32 s) = _sign3009(t);
        uint256 before = usdg.balanceOf(owner);
        vm.prank(relayer);
        uint256 total = m.buyWithAuthorization(t, block.timestamp - 1, block.timestamp + 600, v, r, s);
        assertEq(m.shares(owner, 1), 100e6);
        assertEq(m.shares(relayer, 1), 0);
        assertEq(before - usdg.balanceOf(owner), total); // excess refunded to the owner
        assertEq(m.feesByBuilder(builder), m.feeEscrow());
    }

    function test_3009_slippageRevertsAtomically() public {
        ILMSRMarket.TradeIntent memory t = _intent(10e6); // too low for 100 shares
        (uint8 v, bytes32 r, bytes32 s) = _sign3009(t);
        vm.expectRevert(ILMSRMarket.Slippage.selector);
        m.buyWithAuthorization(t, block.timestamp - 1, block.timestamp + 600, v, r, s);
        assertFalse(usdg.authorizationState(owner, _hash(t))); // still unused
    }

    /// Changing any intent field (or the market) breaks the authorisation (Backend §3.10).
    function testFuzz_intentTamper(uint8 field, uint256 noise) public {
        ILMSRMarket.TradeIntent memory t = _intent(80e6);
        (uint8 v, bytes32 r, bytes32 s) = _sign3009(t);
        field = uint8(bound(field, 0, 6));
        noise = bound(noise, 1, 1e6);
        if (field == 0) t.outcome = 0;
        else if (field == 1) t.shares += noise;
        else if (field == 2) t.maxTotal += noise;
        else if (field == 3) t.deadline += uint64(noise);
        else if (field == 4) t.builder = address(uint160(t.builder) ^ uint160(noise));
        else if (field == 5) t.salt = bytes32(uint256(t.salt) ^ noise);
        else t.owner = relayer;
        vm.prank(relayer);
        vm.expectRevert();
        m.buyWithAuthorization(t, block.timestamp - 1, block.timestamp + 600, v, r, s);
        assertEq(m.shares(owner, 0) + m.shares(owner, 1) + m.shares(relayer, 0) + m.shares(relayer, 1), 0);
    }

    function test_3009_wrongMarket() public {
        ILMSRMarket.TradeIntent memory t = _intent(80e6);
        t.market = address(0xBEEF);
        vm.expectRevert(ILMSRMarket.WrongMarket.selector);
        m.buyWithAuthorization(t, 0, type(uint256).max, 0, 0, 0);
    }

    // ---------------------------------------------------------------- Permit2

    function _signPermit2(ILMSRMarket.TradeIntent memory t, ISignatureTransfer.PermitTransferFrom memory p)
        internal
        view
        returns (bytes memory)
    {
        bytes32 typehash = keccak256(
            abi.encodePacked(
                "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,",
                m.WITNESS_TYPE_STRING()
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                typehash,
                keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, p.permitted.token, p.permitted.amount)),
                address(m),
                p.nonce,
                p.deadline,
                _hash(t)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(ownerPk, keccak256(abi.encodePacked("\x19\x01", IEIP712(PERMIT2).DOMAIN_SEPARATOR(), structHash)));
        return abi.encodePacked(r, s, v);
    }

    function _permit(uint256 amount) internal view returns (ISignatureTransfer.PermitTransferFrom memory) {
        return ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(usdg), amount: amount}),
            nonce: 1,
            deadline: block.timestamp + 600
        });
    }

    function test_permit2_creditsOwner_refundsExcess() public {
        vm.prank(owner);
        usdg.approve(PERMIT2, type(uint256).max);
        ILMSRMarket.TradeIntent memory t = _intent(80e6);
        ISignatureTransfer.PermitTransferFrom memory p = _permit(80e6);
        bytes memory sig = _signPermit2(t, p);
        uint256 before = usdg.balanceOf(owner);
        vm.prank(relayer);
        uint256 total = m.buyWithPermit2(t, p, sig);
        assertEq(m.shares(owner, 1), 100e6);
        assertEq(before - usdg.balanceOf(owner), total);
    }

    function test_permit2_witnessTamper_andWrongToken() public {
        vm.prank(owner);
        usdg.approve(PERMIT2, type(uint256).max);
        ILMSRMarket.TradeIntent memory t = _intent(80e6);
        ISignatureTransfer.PermitTransferFrom memory p = _permit(80e6);
        bytes memory sig = _signPermit2(t, p);
        t.shares += 1;
        vm.expectRevert();
        m.buyWithPermit2(t, p, sig);
        t.shares -= 1;
        MockUSDG other = new MockUSDG();
        p.permitted.token = address(other);
        vm.expectRevert(ILMSRMarket.WrongToken.selector);
        m.buyWithPermit2(t, p, sig);
    }
}
