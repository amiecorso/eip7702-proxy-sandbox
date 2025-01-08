// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EIP7702Proxy} from "../src/EIP7702Proxy.sol";
import {CoinbaseSmartWallet} from "../lib/smart-wallet/src/CoinbaseSmartWallet.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
/**
 * This script upgrades an EOA to a smart contract wallet using an EIP7702Proxy contract and a CoinbaseSmartWallet implementation
 *
 * Prerequisites:
 * 1. For local testing: Anvil node must be running with --odyssey flag
 * 2. For Odyssey testnet: Must have DEPLOYER_PRIVATE_KEY and EOA_PRIVATE_KEY env vars set
 *
 * Running instructions:
 * 
 * Local testing:
 * 1. Start an Anvil node with EIP-7702 support:
 *    ```bash
 *    anvil --odyssey
 *    ```
 * 2. Run this script:
 *    ```bash
 *    forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast --ffi
 *    ```
 *
 * Odyssey testnet:
 * 1. Set environment variables:
 *    ```bash
 *    export DEPLOYER_PRIVATE_KEY=your_deployer_key
 *    export EOA_PRIVATE_KEY=private_key_of_eoa_to_upgrade
 *    ```
 * 2. Run this script:
 *    ```bash
 *    forge script script/Deploy.s.sol --rpc-url https://odyssey.ithaca.xyz --broadcast --ffi
 *    ```
 *
 * What this script does:
 * 1. Deploy the implementation contract (CoinbaseSmartWallet)
 * 2. Deploy the EIP-7702 proxy template (EIP7702Proxy)
 * 3. Generate the required authorization signature
 * 4. Send the initialization transaction wrapped with the EIP-7702 authorization to upgrade the EOA
 * 5. Verify the upgrade by checking the code at the EOA address
 */
contract DeployScript is Script {
    using Strings for address;
    using Strings for uint256;

    // Anvil's default funded accounts (for local testing)
    address constant _ANVIL_ALICE = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 constant _ANVIL_ALICE_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant _ANVIL_DEPLOYER_PK = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    // Chain IDs
    uint256 constant _ANVIL_CHAIN_ID = 31337;
    uint256 constant _ODYSSEY_CHAIN_ID = 911867;

    function run() external {
        // Determine which environment we're in
        uint256 deployerPk;
        uint256 eoaPk;
        address eoa;

        if (block.chainid == _ANVIL_CHAIN_ID) {
            console.log("Using Anvil's pre-funded accounts");
            deployerPk = _ANVIL_DEPLOYER_PK;
            eoaPk = _ANVIL_ALICE_PK;
            eoa = _ANVIL_ALICE;
        } else if (block.chainid == _ODYSSEY_CHAIN_ID) {
            console.log("Using Odyssey testnet with environment variables");
            deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
            eoaPk = vm.envUint("EOA_PRIVATE_KEY");
            eoa = vm.addr(eoaPk);
        } else {
            revert("Unsupported chain ID");
        }

        console.log("EOA to upgrade:", eoa);
        
        // Deploy contracts using deployer
        vm.startBroadcast(deployerPk);

        // 1. Deploy implementation contract
        CoinbaseSmartWallet implementation = new CoinbaseSmartWallet();
        console.log("Implementation deployed at:", address(implementation));

        // 2. Deploy proxy contract
        bytes4 initSelector = CoinbaseSmartWallet.initialize.selector;
        EIP7702Proxy proxy = new EIP7702Proxy(
            address(implementation),
            initSelector
        );
        console.log("Proxy template deployed at:", address(proxy));

        vm.stopBroadcast();

        // Get the current nonce for the EOA
        string[] memory nonceInputs = new string[](5);
        nonceInputs[0] = "cast";
        nonceInputs[1] = "nonce";
        nonceInputs[2] = vm.toString(eoa);
        nonceInputs[3] = "--rpc-url";
        nonceInputs[4] = block.chainid == _ANVIL_CHAIN_ID ? "http://localhost:8545" : "https://odyssey.ithaca.xyz";
        bytes memory nonceBytes = vm.ffi(nonceInputs);
        string memory nonceStr = string(nonceBytes);
        uint256 eoaNonce = vm.parseUint(nonceStr);
        console.log("EOA current nonce:", eoaNonce);
        
        // IMPORTANT: For EIP-7702 initialization, the nonce ordering is critical:
        // 1. The auth signature must use nonce + 1 (next nonce)
        // 2. The initialization transaction must use current nonce
        // This is because the auth needs to remain valid after the transaction consumes the current nonce
        
        // 3. Sign EIP-7702 authorization using cast wallet sign-auth with next nonce
        string[] memory authInputs = new string[](8);
        authInputs[0] = "cast";
        authInputs[1] = "wallet";
        authInputs[2] = "sign-auth";
        authInputs[3] = vm.toString(address(proxy));
        authInputs[4] = "--private-key";
        authInputs[5] = vm.toString(bytes32(eoaPk));
        authInputs[6] = "--nonce";
        authInputs[7] = vm.toString(eoaNonce + 1);  // Auth must use next nonce to remain valid after transaction
        
        console.log("Executing sign-auth command with next nonce:", eoaNonce + 1);
        for (uint i = 0; i < authInputs.length; i++) {
            console.log(authInputs[i]);
        }
        
        bytes memory auth = vm.ffi(authInputs);
        console.log("Generated auth signature:", vm.toString(auth));

        // 5. Send a simple transaction with auth (using cast)
        string[] memory sendInputs = new string[](11);
        sendInputs[0] = "cast";
        sendInputs[1] = "send";
        sendInputs[2] = vm.toString(eoa);  // sending to self
        sendInputs[3] = "--value";
        sendInputs[4] = "0";  // zero value transfer
        sendInputs[5] = "--private-key";
        sendInputs[6] = vm.toString(bytes32(eoaPk));
        sendInputs[7] = "--auth";
        sendInputs[8] = vm.toString(auth);
        sendInputs[9] = "--nonce";
        sendInputs[10] = vm.toString(eoaNonce);  // Transaction uses current nonce, which it will consume

        console.log("Executing auth transaction with current nonce:", eoaNonce);
        for (uint i = 0; i < sendInputs.length; i++) {
            console.log(sendInputs[i]);
        }

        bytes memory result = vm.ffi(sendInputs);
        console.log("Auth transaction sent with result:", vm.toString(result));

        // Move forward one block to ensure the auth transaction is processed
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 12);
        console.log("Moved to next block to process auth");

        // 6. Call initialize directly on the proxy
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(eoa);
        bytes memory initArgs = abi.encode(owners);
        
        console.log("EOA address used in hash:", eoa);
        console.log("Raw init args:", vm.toString(initArgs));
        console.log("ABI encoded hash input:", vm.toString(abi.encode(eoa, initArgs)));
        
        bytes32 initHash = keccak256(abi.encode(address(proxy), initArgs));
        console.log("Init hash:", vm.toString(initHash));

        // Sign the hash directly without EIP-712 domain
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPk, initHash);
        console.log("Signature components:");
        console.log("v:", v);
        console.log("r:", vm.toString(r));
        console.log("s:", vm.toString(s));
        
        // Let's verify the signature ourselves before sending
        bytes memory initSignature = abi.encodePacked(r, s, v);
        
        // For debugging, let's try to recover using the hash
        address recovered = ECDSA.recover(initHash, initSignature);
        console.log("Recovered:", recovered);

        // Call initialize directly through Foundry
        // Set the correct nonce since we mixed FFI and broadcast
        vm.setNonce(eoa, uint64(eoaNonce + 2));  // Auth + transaction consumed two nonces, so we use the next one
        console.log("Setting nonce to:", eoaNonce + 2);
        vm.startBroadcast(eoaPk);
        
        // Cast the EOA address to the proxy interface and call initialize
        EIP7702Proxy(payable(eoa)).initialize(initArgs, initSignature);
        console.log("Initialize called directly with nonce:", eoaNonce + 2);

        vm.stopBroadcast();

        // Verify EOA has been upgraded by checking its code
        string[] memory codeInputs = new string[](5);
        codeInputs[0] = "cast";
        codeInputs[1] = "code";
        codeInputs[2] = vm.toString(eoa);
        codeInputs[3] = "--rpc-url";
        codeInputs[4] = block.chainid == _ANVIL_CHAIN_ID ? "http://localhost:8545" : "https://odyssey.ithaca.xyz";

        bytes memory code = vm.ffi(codeInputs);
        console.log("EOA code after upgrade:");
        console.log(vm.toString(code));
        
        if (code.length > 0) {
            console.log("[OK] Success: EOA has been upgraded to a smart contract!");
            
            // Verify ownership
            bool isOwner = CoinbaseSmartWallet(payable(eoa)).isOwnerAddress(eoa);
            if (isOwner) {
                console.log("[OK] Success: EOA has been added as an owner!");
            } else {
                console.log("[ERROR] Error: EOA is not an owner of the smart contract!");
            }
        } else {
            console.log("[ERROR] Error: EOA code is still empty!");
        }
    }
}

// Helper struct to match the expected tuple format
struct DeploymentData {
    bytes code;
    address addr;
    uint256 value;
} 