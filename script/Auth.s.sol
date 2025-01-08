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
 *    forge script script/Auth.s.sol --rpc-url http://localhost:8545 --broadcast --ffi
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
 *    forge script script/Auth.s.sol --rpc-url https://odyssey.ithaca.xyz --broadcast --ffi
 *    ```
 *
 * What this script does:
 * 1. Deploy the implementation contract (CoinbaseSmartWallet)
 * 2. Deploy the EIP-7702 proxy template (EIP7702Proxy)
 * 3. Generate the required authorization signature
 * 4. Send this signed auth object to upgrade the EOA
 * 5. Verify the upgrade by checking the code at the EOA address
 */
contract Auth is Script {
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
        
        // Deploy contracts using separate deployer, to avoid nonce issues with the EOA that happen
        // when mixing broadcast and FFI in Foundry.
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
        
        // IMPORTANT: For EIP-7702 initialization, the nonce ordering matters:
        // 1. The transaction must use current nonce
        // 2. The auth signature must use nonce + 1 (next nonce)
        // This is because the auth needs to remain valid after the transaction containing it consumes the current nonce
        
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
        } else {
            console.log("[ERROR] Error: EOA code is still empty!");
        }
    }
}