// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {EIP7702Proxy} from "../src/EIP7702Proxy.sol";
import {CoinbaseSmartWallet} from "../lib/smart-wallet/src/CoinbaseSmartWallet.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

contract GenerateInitData is Script {
    function run() external {
        uint256 alicePk = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        address alice = vm.addr(alicePk);
        uint256 bobPk = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
        address bob = vm.addr(bobPk);
        console2.log("address bob", bob);
        // Get the proxy address from env
        address proxyAddr = 0x261D8c5e9742e6f7f1076Fa1F560894524e19cad;

        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(bob);
        bytes memory initArgs = abi.encode(owners);
        bytes32 initHash = keccak256(abi.encode(proxyAddr, initArgs));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, initHash);

        bytes memory initSignature = abi.encodePacked(r, s, v);

        // Output the data in a format ready for cast send
        string memory encodedInitCall = vm.toString(
            abi.encodeWithSelector(
                EIP7702Proxy.initialize.selector,
                initArgs,
                initSignature
            )
        );

        console2.log("=== Copy everything between the lines below ===");
        console2.log("----------------------------------------");
        console2.log(encodedInitCall);
        console2.log("----------------------------------------");
        console2.log("\nUse this data with cast send like this:");
        console2.log(
            "cast send $PROXY_TEMPLATE_ADDRESS",
            encodedInitCall,
            "--private-key $ALICE_PK"
        );
    }
}
