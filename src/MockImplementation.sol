// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {UUPSUpgradeable} from "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

contract MockImplementation is Initializable, UUPSUpgradeable {
    address public owner;
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) public initializer {
        owner = _owner;
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == owner, "Unauthorized");
    }
} 