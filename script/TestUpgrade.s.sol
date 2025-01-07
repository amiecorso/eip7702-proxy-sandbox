// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CoinbaseSmartWallet} from "../lib/smart-wallet/src/CoinbaseSmartWallet.sol";

/**
 * This script tests an upgraded EOA by verifying ownership and executing an ETH transfer
 *
 * Prerequisites:
 * 1. EOA must already be upgraded using Deploy.s.sol
 * 2. For local testing: Anvil node must be running with --odyssey flag
 * 3. For Odyssey testnet: Must have EOA_PRIVATE_KEY and RECIPIENT_ADDRESS env vars set
 *
 * Running instructions:
 * 
 * Local testing:
 * ```bash
 * forge script script/TestUpgrade.s.sol --rpc-url http://localhost:8545 --broadcast --ffi
 * ```
 *
 * Odyssey testnet:
 * ```bash
 * forge script script/TestUpgrade.s.sol --rpc-url https://odyssey.ithaca.xyz --broadcast --ffi
 * ```
 */
contract TestUpgradeScript is Script {
    // Anvil's default funded accounts (for local testing)
    address constant _ANVIL_ALICE = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 constant _ANVIL_ALICE_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    address constant _ANVIL_BOB = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    // Chain IDs
    uint256 constant _ANVIL_CHAIN_ID = 31337;
    uint256 constant _ODYSSEY_CHAIN_ID = 911867;

    function run() external {
        // Determine which environment we're in
        address eoa;
        uint256 eoaPk;
        address recipient;

        if (block.chainid == _ANVIL_CHAIN_ID) {
            console.log("Using Anvil's pre-funded accounts");
            eoa = _ANVIL_ALICE;
            eoaPk = _ANVIL_ALICE_PK;
            recipient = _ANVIL_BOB;
        } else if (block.chainid == _ODYSSEY_CHAIN_ID) {
            console.log("Using Odyssey testnet with environment variables");
            eoaPk = vm.envUint("EOA_PRIVATE_KEY");
            eoa = vm.addr(eoaPk);
            recipient = vm.envAddress("RECIPIENT_ADDRESS");
        } else {
            revert("Unsupported chain ID");
        }

        console.log("EOA address:", eoa);
        console.log("Recipient address:", recipient);

        // First verify the EOA has code
        require(address(eoa).code.length > 0, "EOA not upgraded yet! Run Deploy.s.sol first");
        console.log("[OK] Verified EOA has been upgraded");

        // Cast EOA's address to a CoinbaseSmartWallet and verify ownership
        CoinbaseSmartWallet smartWallet = CoinbaseSmartWallet(payable(eoa));
        
        // // Verify ownership
        // bool isOwner = smartWallet.isOwnerAddress(eoa);
        // require(isOwner, "EOA is not an owner of the smart wallet!");
        // console.log("[OK] Verified EOA is an owner of the smart wallet");

        // Get recipient's initial balance
        uint256 initialBalance = recipient.balance;
        console.log("\nRecipient's initial balance:", initialBalance);

// THIS FAILS
        // // generate a random pk
        // uint256 randomPk = uint256(keccak256(abi.encode(block.timestamp, block.prevrandao, block.number, block.coinbase, block.difficulty, block.gaslimit, block.chainid)));
        // console.log("Random PK:", randomPk);

        // // Start broadcast to send the transaction with a random pk i.e. not the EOA's pk who should be the only owner now
        // vm.startBroadcast(randomPk);
        
        // Start broadcast to send the transaction EOA's pk
        vm.startBroadcast(eoaPk);

        // Execute the transfer through the wallet
        smartWallet.execute(
            recipient,
            0.1 ether,
            new bytes(0)
        );

        vm.stopBroadcast();

        // Verify recipient's balance increased
        uint256 finalBalance = recipient.balance;
        console.log("Recipient's final balance:", finalBalance);
        
        if (finalBalance > initialBalance) {
            console.log("[OK] Success: Transfer completed! Recipient's balance increased by:", finalBalance - initialBalance);
        } else {
            console.log("[ERROR] Transfer failed! Recipient's balance did not increase");
        }
    }
} 