// SPDX-License-Identifier: MIT

import {Script} from "forge-std/Script.sol";
import {EdenPL, IHasher, IVerifier, UserDW} from "../src/EdenPL.sol";
import {EdenEVM} from "../src/EdenEVM.sol";
import {Groth16Verifier} from "../src/verifier.sol";
import {EdenVault} from "../src/EdenVault.sol";

pragma solidity ^0.8.23;

contract DeployScript is Script {
    EdenPL public EPL;
    EdenEVM public EVPL;

    Groth16Verifier public verifier;
    address public mimcHasher;

    address constant ethsepoliaMailbox = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;
    address constant baseSepoliaMailbox = 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93;

    uint64 constant EthSepoliaChainId = 16015286601757825753;
    address constant destinationETHAddresLinkToken = 0xD90f34B559C7b964cb705c5cadaCb682950324f9;

    address constant ethSepoliaLinkToken = 0x779877A7B0D9E8603169DdbD7836e478b4624789;

    address constant destinationAddressETHToken = 0x4418Ba6d81b2C3C031A969203d26A49bB8055d20;

    address constant linkSepolia = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address constant linkBase = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;

    address constant avaxLink = 0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846;
    address constant avalancheRouter = 0xF694E193200268f9a4868e4Aa017A0118C9a8177;

    

    // Lets go again, our last run!
    // ETH SEPOLIA FIRST

    //
    function run() external {
        if (block.chainid == 11155111) {
            vm.startBroadcast();

            string[] memory inputs = new string[](2);
            inputs[0] = "node";
            inputs[1] = "forge-ffi-scripts/deployMimcsponge.js";

            bytes memory mimcspongeBytecode = vm.ffi(inputs);

            // Deploy the contract using the bytecode
            assembly {
                let success := create(0, add(mimcspongeBytecode, 0x20), mload(mimcspongeBytecode))
                if iszero(success) { revert(0, 0) }
                sstore(mimcHasher.slot, success)
            }

            verifier = new Groth16Verifier();

            EPL = new EdenPL(
                IVerifier(address(verifier)), IHasher(mimcHasher), address(ethSepoliaLinkToken), 20, ethsepoliaMailbox
            );
        } else if (block.chainid == 84532) {
            vm.startBroadcast();

            EVPL = new EdenEVM(
                address(linkBase), address(baseSepoliaMailbox), EthSepoliaChainId, destinationETHAddresLinkToken
            );
        } else {
            vm.startBroadcast();

            EVPL = new EdenEVM(
                address(avaxLink), address(avalancheRouter), EthSepoliaChainId, destinationETHAddresLinkToken
            );
        }
    }
}
