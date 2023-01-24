// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
// import "forge-std/console.sol";
import "../src/CollatzPuzzle.sol";
import "../src/CollatzDeployer.sol";

contract CollatzPuzzleTest is Test {
    CollatzDeployer collatzDeployer;
    CollatzPuzzle collatzPuzzle;

    address exploitContractAddress;

    function setUp() public {
        collatzDeployer = new CollatzDeployer();
        collatzPuzzle = new CollatzPuzzle();

        exploitContractAddress = collatzDeployer.deployExploiterContract();
    }

    function testExploit() public {
        bool exploited = collatzPuzzle.callMe(exploitContractAddress);
        assertTrue(exploited);
    }
}