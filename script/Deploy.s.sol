// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EIP7702Proxy} from "../src/EIP7702Proxy.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract DeployScript is Script {
    using Strings for address;
    using Strings for uint256;

    // Anvil's default funded accounts
    address constant ALICE = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 constant ALICE_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant BOB_PK = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    // Use a different deployer for initial contracts
    uint256 constant DEPLOYER_PK = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    function run() external {
        uint256 eoa_private_key;

        // Check if we're on anvil by checking chainid
        if (block.chainid == 31337) {
            console.log("Using Anvil's pre-funded accounts");
            eoa_private_key = ALICE_PK;
        } else {
            console.log("Using accounts from environment variables");
            eoa_private_key = vm.envUint("EOA_PRIVATE_KEY");
        }

        address eoa = vm.addr(eoa_private_key);
        console.log("EOA address:", eoa);
        
        // Deploy contracts using a separate deployer
        vm.startBroadcast(DEPLOYER_PK);

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

        // Get the current nonce for the EOA (Alice)
        string[] memory nonceInputs = new string[](5);
        nonceInputs[0] = "cast";
        nonceInputs[1] = "nonce";
        nonceInputs[2] = vm.toString(eoa);
        nonceInputs[3] = "--rpc-url";
        nonceInputs[4] = "http://localhost:8545";
        bytes memory nonceBytes = vm.ffi(nonceInputs);
        string memory nonceStr = string(nonceBytes);
        uint256 eoaNonce = vm.parseUint(nonceStr);
        console.log("EOA current nonce:", eoaNonce);
        
        // 3. Sign EIP-7702 authorization using cast wallet sign-auth
        string[] memory authInputs = new string[](8);
        authInputs[0] = "cast";
        authInputs[1] = "wallet";
        authInputs[2] = "sign-auth";
        authInputs[3] = vm.toString(address(proxy));
        authInputs[4] = "--private-key";
        authInputs[5] = vm.toString(bytes32(eoa_private_key));
        authInputs[6] = "--nonce";
        authInputs[7] = vm.toString(eoaNonce);
        
        console.log("Executing sign-auth command:");
        for (uint i = 0; i < authInputs.length; i++) {
            console.log(authInputs[i]);
        }
        
        bytes memory auth = vm.ffi(authInputs);
        console.log("Generated auth signature:", vm.toString(auth));

        // 4. Prepare initialization args for the proxy
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(eoa);
        bytes32 initHash = keccak256(abi.encode(eoa, owners));
        
        // Get signature components
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoa_private_key, initHash);
        bytes memory initSignature = abi.encodePacked(r, s, v);

        // Get Bob's current nonce for the final transaction
        nonceInputs[2] = vm.toString(vm.addr(BOB_PK));
        nonceBytes = vm.ffi(nonceInputs);
        nonceStr = string(nonceBytes);
        uint256 bobNonce = vm.parseUint(nonceStr);
        console.log("Bob's current nonce:", bobNonce);

        // 5. Send the EIP-7702 transaction
        string[] memory sendInputs = new string[](12);
        sendInputs[0] = "cast";
        sendInputs[1] = "send";
        sendInputs[2] = vm.toString(eoa);
        sendInputs[3] = "initialize(bytes,bytes)";
        sendInputs[4] = vm.toString(abi.encode(owners));
        sendInputs[5] = vm.toString(initSignature);
        sendInputs[6] = "--private-key";
        sendInputs[7] = vm.toString(bytes32(BOB_PK));
        sendInputs[8] = "--auth";
        sendInputs[9] = vm.toString(auth);
        sendInputs[10] = "--nonce";
        sendInputs[11] = vm.toString(bobNonce);

        console.log("Executing send command:");
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
        codeInputs[4] = "http://localhost:8545";

        bytes memory code = vm.ffi(codeInputs);
        console.log("EOA code after upgrade:");
        console.log(vm.toString(code));
        
        if (code.length > 0) {
            console.log("Success: EOA has been upgraded to a smart contract!");
        } else {
            console.log("Error: EOA code is still empty!");
        }
    }
}

// Helper struct to match the expected tuple format
struct tuple {
    bytes code;
    address addr;
    uint256 value;
} 