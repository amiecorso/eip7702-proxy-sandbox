// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {EIP7702ProxyBase} from "../base/EIP7702ProxyBase.sol";
import {EIP7702Proxy} from "../../src/EIP7702Proxy.sol";
import {CoinbaseSmartWallet} from "../../lib/smart-wallet/src/CoinbaseSmartWallet.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {console2} from "forge-std/console2.sol";

contract InitializeTest is EIP7702ProxyBase {
    function testSucceedsWithValidSignature() public {
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes memory signature = _signInitData(_EOA_PRIVATE_KEY, initArgs);
        
        vm.prank(_eoa);
        EIP7702Proxy(_eoa).initialize(initArgs, signature);
        
        // Verify initialization through implementation at the EOA's address
        CoinbaseSmartWallet wallet = CoinbaseSmartWallet(payable(_eoa));
        assertTrue(wallet.isOwnerAddress(_newOwner), "New owner should be owner after initialization");
    }
    
    function testRevertsWithInvalidSignature() public {
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes memory signature = hex"deadbeef"; // Invalid signature
        
        vm.prank(_eoa);
        vm.expectRevert(); // Should revert with signature verification error
        EIP7702Proxy(_eoa).initialize(initArgs, signature);
    }
    
    function testRevertsWithWrongSigner() public {
        // Create signature with different private key
        uint256 wrongPk = 0xC0FFEE;  // Using a different key than either EOA or new owner
        
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes32 initHash = keccak256(abi.encode(_eoa, initArgs));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, initHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        vm.prank(_eoa);
        vm.expectRevert(); // Should revert with signature verification error
        EIP7702Proxy(_eoa).initialize(initArgs, signature);
    }
    
    function testCanOnlyBeCalledOnce() public {
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes memory signature = _signInitData(_EOA_PRIVATE_KEY, initArgs);
        
        vm.prank(_eoa);
        EIP7702Proxy(_eoa).initialize(initArgs, signature);
        
        // Try to initialize again
        vm.prank(_eoa);
        vm.expectRevert(CoinbaseSmartWallet.Initialized.selector);
        EIP7702Proxy(_eoa).initialize(initArgs, signature);
    }
    
    function testGasForInitialize() public {
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes memory signature = _signInitData(_EOA_PRIVATE_KEY, initArgs);
        
        // Calculate calldata gas cost
        bytes memory callData = abi.encodeWithSelector(
            EIP7702Proxy.initialize.selector,
            initArgs,
            signature
        );
        uint256 calldataGas = 0;
        for (uint i = 0; i < callData.length; i++) {
            if (callData[i] == 0) {
                calldataGas += 16; // pretend worst case all nonzero
            } else {
                calldataGas += 16;
            }
        }
        
        vm.prank(_eoa);
        uint256 gasBefore = gasleft();
        EIP7702Proxy(_eoa).initialize(initArgs, signature);
        uint256 executionGas = gasBefore - gasleft();
        
        console2.log("Gas breakdown for initialize:");
        console2.log("Base transaction cost: ", uint(21000));
        console2.log("Calldata cost: ", calldataGas);
        console2.log("Execution cost: ", executionGas);
        console2.log("Total gas cost: ", 21000 + calldataGas + executionGas);
    }
} 