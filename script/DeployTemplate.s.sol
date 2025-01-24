// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EIP7702Proxy} from "../src/EIP7702Proxy.sol";
import {CoinbaseSmartWallet} from "../lib/smart-wallet/src/CoinbaseSmartWallet.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

/**
 * This script deploys an EIP7702Proxy contract and its CoinbaseSmartWallet implementation
 *
 * 1. Start an Anvil node with EIP-7702 support:
 *    ```bash
 *    anvil --odyssey
 *    ```
 * 2. Run this script:
 *    ```bash
 *    forge script script/DeployTemplate.s.sol --broadcast --rpc-url http://localhost:8545
 *    ```
 */
contract DeployTemplate is Script {
    using Strings for address;
    using Strings for uint256;

    // Deploy with an account that won't conflict with Alice or Bob in later example
    uint256 constant ANVIL_DEPLOYER_PK =
        0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    EIP7702Proxy proxy;

    function run() external {
        vm.startBroadcast(ANVIL_DEPLOYER_PK);

        CoinbaseSmartWallet implementation = new CoinbaseSmartWallet();
        console.log("Implementation deployed at:", address(implementation));

        // 2. Deploy proxy contract with create2 for deterministic address
        bytes4 initSelector = CoinbaseSmartWallet.initialize.selector;
        proxy = new EIP7702Proxy(address(implementation), initSelector);
        console.log("Proxy deployed at:", address(proxy));

        vm.stopBroadcast();
    }
}
