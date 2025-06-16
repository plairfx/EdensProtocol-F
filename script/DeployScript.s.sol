// SPDX-License-Identifier: MIT

import {Script} from "forge-std/Script.sol";
import {EdenPL, IHasher, IVerifier, UserDW} from "../src/EdenPL.sol";
import {EdenEVM} from "../src/EdenEVM.sol";
import {Groth16Verifier} from "../src/verifier.sol";
import {EdenVault} from "../src/EdenVault.sol";
import {
    MockHyperlaneEnvironment,
    MockMailbox,
    TypeCasts
} from "lib/hyperlane-monorepo/solidity/contracts/mock/MockHyperlaneEnvironment.sol";

pragma solidity ^0.8.23;

contract DeployScript is Script {
    EdenPL public EPL;
    EdenEVM public EVPL;

    Groth16Verifier public verifier;
    address public mimcHasher;

    address constant ethsepoliaMailbox = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;
    address constant baseSepoliaMailbox = 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93;

    uint64 constant EthSepoliaChainId = 16015286601757825753;
    address constant destinationAddresLinkToken = 0x2C0f9385a3Cb6E0d17b7db1C489bEB233A8c6e7c;
    address constant destinationAddressETHToken = 0xd5C65F9c5e6CCBBD5400FA599b71A1f44EEad717;

    address constant linkSepolia = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address constant linkBase = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;

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

            EPL = new EdenPL(IVerifier(address(verifier)), IHasher(mimcHasher), address(0x0), 20, ethsepoliaMailbox);
        } else if (block.chainid == 84532) {
            vm.startBroadcast();

            EVPL = new EdenEVM(address(0x0), address(baseSepoliaMailbox), EthSepoliaChainId, destinationAddressETHToken);
        } else {}
    }
}
