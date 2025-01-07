// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EIP7702Proxy} from "../src/EIP7702Proxy.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

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
    address constant ANVIL_ALICE = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 constant ANVIL_ALICE_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant ANVIL_DEPLOYER_PK = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    // Chain IDs
    uint256 constant ANVIL_CHAIN_ID = 31337;
    uint256 constant ODYSSEY_CHAIN_ID = 911867;

    function run() external {
        // Determine which environment we're in
        uint256 deployerPk;
        uint256 eoaPk;
        address eoa;

        if (block.chainid == ANVIL_CHAIN_ID) {
            console.log("Using Anvil's pre-funded accounts");
            deployerPk = ANVIL_DEPLOYER_PK;
            eoaPk = ANVIL_ALICE_PK;
            eoa = ANVIL_ALICE;
        } else if (block.chainid == ODYSSEY_CHAIN_ID) {
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
        nonceInputs[4] = block.chainid == ANVIL_CHAIN_ID ? "http://localhost:8545" : "https://odyssey.ithaca.xyz";
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

        // 4. Prepare initialization args for the proxy
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(eoa);
        bytes memory initArgs = abi.encode(owners);
        bytes32 initHash = keccak256(abi.encode(address(proxy), initArgs));
        
        // Get signature components
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPk, initHash);
        bytes memory initSignature = abi.encodePacked(r, s, v);

        // 5. Send the EIP-7702 transaction using current nonce
        string[] memory sendInputs = new string[](12);
        sendInputs[0] = "cast";
        sendInputs[1] = "send";
        sendInputs[2] = vm.toString(eoa);
        sendInputs[3] = "initialize(bytes,bytes)";
        sendInputs[4] = vm.toString(initArgs);
        sendInputs[5] = vm.toString(initSignature);
        sendInputs[6] = "--private-key";
        sendInputs[7] = vm.toString(bytes32(eoaPk));
        sendInputs[8] = "--auth";
        sendInputs[9] = vm.toString(auth);
        sendInputs[10] = "--nonce";
        sendInputs[11] = vm.toString(eoaNonce);  // Transaction uses current nonce, which it will consume

        console.log("Executing send command with current nonce:", eoaNonce);
        for (uint i = 0; i < sendInputs.length; i++) {
            console.log(sendInputs[i]);
        }

        bytes memory result = vm.ffi(sendInputs);
        console.log("Transaction sent with result:", vm.toString(result));

        // Verify EOA has been upgraded by checking its code
        string[] memory codeInputs = new string[](5);
        codeInputs[0] = "cast";
        codeInputs[1] = "code";
        codeInputs[2] = vm.toString(eoa);
        codeInputs[3] = "--rpc-url";
        codeInputs[4] = block.chainid == ANVIL_CHAIN_ID ? "http://localhost:8545" : "https://odyssey.ithaca.xyz";

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

// Helper struct to match the expected tuple format
struct tuple {
    bytes code;
    address addr;
    uint256 value;
} 