// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {EIP7702Proxy} from "../src/EIP7702Proxy.sol";
import {MockImplementation} from "../src/MockImplementation.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract DeployScript is Script {
    using Strings for address;
    using Strings for uint256;
    using Strings for bytes;

    function run() external {
        // Get private keys from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 eoa_private_key = vm.envUint("EOA_PRIVATE_KEY");
        address eoa = vm.addr(eoa_private_key);
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy implementation contract
        MockImplementation implementation = new MockImplementation();
        console.log("Implementation deployed at:", address(implementation));

        // 2. Get the proxy creation code (not deployed)
        bytes memory proxyCode = type(EIP7702Proxy).creationCode;
        // Encode constructor arguments
        bytes4 initSelector = MockImplementation.initialize.selector;
        bytes memory constructorArgs = abi.encode(address(implementation), initSelector);
        // Combine creation code with encoded constructor args
        proxyCode = bytes.concat(proxyCode, constructorArgs);

        vm.stopBroadcast();

        // 3. Sign EIP-7702 authorization for the EOA to use proxy code
        bytes memory auth = vm.sign(
            eoa_private_key,
            keccak256(proxyCode)
        ).sig;

        // 4. Prepare initialization args for the proxy
        bytes memory initArgs = abi.encode(eoa); // set EOA as owner
        bytes32 initHash = keccak256(abi.encode(eoa, initArgs));
        bytes memory initSignature = vm.sign(eoa_private_key, initHash).sig;

        // 5. Use cast through FFI to send the EIP-7702 transaction
        // First encode the initialization args
        string[] memory inputs = new string[](3);
        inputs[0] = "cast";
        inputs[1] = "abi-encode";
        inputs[2] = string.concat(
            '"(bytes,bytes)" "(',
            vm.toString(initArgs),
            ',',
            vm.toString(initSignature),
            ')"'
        );
        
        bytes memory encoded = vm.ffi(inputs);
        
        // Now send the transaction
        string[] memory sendInputs = new string[](9);
        sendInputs[0] = "cast";
        sendInputs[1] = "send";
        sendInputs[2] = vm.toString(eoa);
        sendInputs[3] = "initialize(bytes,bytes)";
        sendInputs[4] = vm.toString(encoded);
        sendInputs[5] = "--private-key";
        sendInputs[6] = vm.toString(deployerPrivateKey);
        sendInputs[7] = "--auth";
        sendInputs[8] = vm.toString(auth);

        bytes memory result = vm.ffi(sendInputs);
        console.log("Transaction sent with result:", vm.toString(result));
        console.log("EOA upgraded to proxy at:", eoa);
    }
}

// Helper struct to match the expected tuple format
struct tuple {
    bytes code;
    address addr;
    uint256 value;
} 