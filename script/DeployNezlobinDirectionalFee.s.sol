// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "../utils/HookMiner.sol";
import {NezlobinDirectionalFee} from "../src/NezlobinDirectionalFee.sol";
import "forge-std/console.sol";

contract DeployNezlobinDirectionalFee is Script {
    // Address of PoolManager deployed on Sepolia
    PoolManager manager =
        PoolManager(0xCa6DBBe730e31fDaACaA096821199EEED5AD84aE);
    address priceFeedAddress = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    function setUp() public {
        // Set up the hook flags you wish to enable
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.AFTER_INITIALIZE_FLAG |
                Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG
        );

        // Find an address + salt using HookMiner that meets our flags criteria
        address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(NezlobinDirectionalFee).creationCode,
            abi.encode(address(manager))
        );

        // Deploy our hook contract with the given `salt` value
        vm.startBroadcast();
        NezlobinDirectionalFee hook = new NezlobinDirectionalFee{salt: salt}(
            manager,
            priceFeedAddress
        );
        console.log("hookAddress:", address(hook));
        console.log("create2Address:", hookAddress);
        // Ensure it got deployed to our pre-computed address
        require(address(hook) == hookAddress, "hook address mismatch");
        vm.stopBroadcast();
    }

    function run() public {
        console.log("Hello");
    }
}
