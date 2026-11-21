// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AggregatorV3Interface} from "@chainlink/AggregatorV3Interface.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {Test} from "forge-std/Test.sol";
import {ISignatureTransfer} from "permit2/ISignatureTransfer.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

contract SmokeTest is Test {
    function test_dependenciesResolve() public pure {
        assertEq(
            IPyth.parsePriceFeedUpdatesUnique.selector,
            bytes4(keccak256("parsePriceFeedUpdatesUnique(bytes[],bytes32[],uint64,uint64)"))
        );
        assertEq(AggregatorV3Interface.latestRoundData.selector, bytes4(keccak256("latestRoundData()")));
        assertTrue(type(ISignatureTransfer).interfaceId != bytes4(0));
        assertEq(FixedPointMathLib.lnWad(1e18), 0);
    }
}
