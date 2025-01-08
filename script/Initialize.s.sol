// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CoinbaseSmartWallet} from "../lib/smart-wallet/src/CoinbaseSmartWallet.sol";
import {EIP7702Proxy} from "../src/EIP7702Proxy.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
/**
 * This script tests an upgraded EOA by verifying ownership and executing an ETH transfer
 *
 * Prerequisites:
 * 1. EOA must already be upgraded using Deploy.s.sol
 * 2. For local testing: Anvil node must be running with --odyssey flag
 * 3. For Odyssey testnet: Must have EOA_PRIVATE_KEY env var set
 *
 * Running instructions:
 * 
 * Local testing:
 * ```bash
 * forge script script/Initialize.s.sol --rpc-url http://localhost:8545 --broadcast --ffi
 * ```
 *
 * Odyssey testnet:
 * ```bash
 * forge script script/Initialize.s.sol --rpc-url https://odyssey.ithaca.xyz --broadcast --ffi
 * ```
 */
contract Initialize is Script {
    // Anvil's default funded accounts (for local testing)
    address constant _ANVIL_ALICE = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 constant _ANVIL_ALICE_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    // Chain IDs
    uint256 constant _ANVIL_CHAIN_ID = 31337;
    uint256 constant _ODYSSEY_CHAIN_ID = 911867;

    // Deterministic proxy addresses for different environments
    address constant _PROXY_ADDRESS_ANVIL = 0x2d95f129bCEbD5cF7f395c7B34106ac1DCfb0CA9;
    address constant _PROXY_ADDRESS_ODYSSEY = 0x6894C39b879fc14e7B107C16Dc6D50140D466d2a;

    function run() external {
        // Determine which environment we're in
        address eoa;
        uint256 eoaPk;
        address proxyAddr;

        if (block.chainid == _ANVIL_CHAIN_ID) {
            console.log("Using Anvil's pre-funded accounts");
            eoa = _ANVIL_ALICE;
            eoaPk = _ANVIL_ALICE_PK;
            proxyAddr = _PROXY_ADDRESS_ANVIL;
        } else if (block.chainid == _ODYSSEY_CHAIN_ID) {
            console.log("Using Odyssey testnet with environment variables");
            eoaPk = vm.envUint("EOA_PRIVATE_KEY");
            eoa = vm.addr(eoaPk);
            proxyAddr = _PROXY_ADDRESS_ODYSSEY;
        } else {
            revert("Unsupported chain ID");
        }

        console.log("EOA address:", eoa);
        console.log("Using proxy template at:", proxyAddr);

        // First verify the EOA has code
        require(address(eoa).code.length > 0, "EOA not upgraded yet! Run Auth.s.sol first");
        console.log("[OK] Verified EOA has been upgraded");

        // Create and sign the initialize data
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(eoa);
        bytes memory initArgs = abi.encode(owners);
        bytes32 initHash = keccak256(abi.encode(proxyAddr, initArgs));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPk, initHash);
        
        bytes memory initSignature = abi.encodePacked(r, s, v);
        
        // Try to recover ourselves before sending
        address recovered = ECDSA.recover(initHash, initSignature);
        console.log("Recovered:", recovered);

        // Start broadcast with EOA's private key to call initialize
        vm.startBroadcast(eoaPk);
        
        // Try to initialize, but handle the case where it's already initialized
        try EIP7702Proxy(payable(eoa)).initialize(initArgs, initSignature) {
            console.log("[OK] Successfully initialized the smart wallet");
        } catch Error(string memory reason) {
            console.log("[INFO] Initialize call reverted with reason:", reason);
        } catch (bytes memory) {
            console.log("[INFO] Initialization failed: EOA may already have been initialized");
        }

        vm.stopBroadcast();
        
        // Verify ownership
        CoinbaseSmartWallet smartWallet = CoinbaseSmartWallet(payable(eoa));
        bool isOwner = smartWallet.isOwnerAddress(eoa);
        require(isOwner, "EOA is not an owner of the smart wallet!");
        console.log("[OK] Verified EOA is an owner of the smart wallet");

        // Verifying that the EOA can call `execute` on the smart wallet isn't an interesting test because
        // the EOA passes the `_isOwnerOrEntrypoint` check by way of being the address of the smart wallet.
    }
} 