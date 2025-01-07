// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @title EIP-7702 Upgrade Test Script
 * @notice This script tests that an EOA previously upgraded to a CoinbaseSmartWallet can execute transactions
 *
 * Prerequisites:
 * 1. Must have already run Deploy.s.sol successfully to upgrade the EOA
 * 2. The Anvil node must still be running with the same state
 *
 * Running instructions:
 * 1. Start an Anvil node with EIP-7702 support:
 *    ```bash
 *    anvil --odyssey
 *    ```
 *
 * 2. Run the deployment script first:
 *    ```bash
 *    forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast --ffi
 *    ```
 *
 * 3. Then run this test script:
 *    ```bash
 *    forge script script/TestUpgrade.s.sol --rpc-url http://localhost:8545 --broadcast
 *    ```
 *
 * What this script does:
 * 1. Verifies that Alice's EOA has been upgraded to a smart wallet
 * 2. Attempts to send 0.1 ETH from Alice's wallet to Bob via the code of the smart wallet
 * 3. Verifies the transfer was successful by checking Bob's balance
 */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

contract TestUpgradeScript is Script {
    // Anvil's default funded accounts (same as Deploy.s.sol)
    address constant ALICE = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 constant ALICE_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    address constant BOB = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    function run() external {
        // First verify the EOA has code
        require(address(ALICE).code.length > 0, "EOA not upgraded yet! Run Deploy.s.sol first");
        console.log("[OK] Verified EOA has been upgraded");

        // Get Bob's initial balance
        uint256 initialBalance = BOB.balance;
        console.log("Bob's initial balance:", initialBalance);

        // Cast Alice's address to a CoinbaseSmartWallet
        CoinbaseSmartWallet wallet = CoinbaseSmartWallet(payable(ALICE));

        // Start broadcast to send the transaction as Alice
        vm.startBroadcast(ALICE_PK);
        
        // Execute the transfer through the wallet
        wallet.execute(
            BOB,
            0.1 ether,
            new bytes(0)
        );

        vm.stopBroadcast();

        // Verify Bob's balance increased
        uint256 finalBalance = BOB.balance;
        console.log("Bob's final balance:", finalBalance);
        
        if (finalBalance > initialBalance) {
            console.log("[OK] Success: Transfer completed! Bob's balance increased by:", finalBalance - initialBalance);
        } else {
            console.log("[ERROR] Transfer failed! Bob's balance did not increase");
        }
    }
} 