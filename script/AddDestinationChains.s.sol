// SPDX-License-Identifier: MIT

import {Script} from "forge-std/Script.sol";
import {EdenPL, IHasher, IVerifier, UserDW} from "../src/EdenPL.sol";
import {EdenEVM} from "../src/EdenEVM.sol";
import {Groth16Verifier} from "../src/verifier.sol";
import {EdenVault} from "../src/EdenVault.sol";

pragma solidity ^0.8.23;

contract AddDestinationChains is Script {
    EdenPL public EPL;
    address public mimcHasher;

    address payable public _EPL = payable(address(0x4418Ba6d81b2C3C031A969203d26A49bB8055d20));
    address payable public _EVPL = payable(address(0xD90f34B559C7b964cb705c5cadaCb682950324f9));
    address constant ethsepoliaMailbox = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;
    address constant baseSepoliaMailbox = 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93;

    uint64 constant EthSepoliaChainId = 16015286601757825753;
    address constant destinationAddresLinkToken = 0x2C0f9385a3Cb6E0d17b7db1C489bEB233A8c6e7c; // fix this
    address constant destinationAddressETHToken = 0x4418Ba6d81b2C3C031A969203d26A49bB8055d20;
    uint64 constant BaseSepoliaChainId = 10344971235874465080;
    address constant EdenEVMaddressETH = 0xA17Dd3Cc59951b0ED78D3bC9f6Ee944fF53FD1f2;

    address constant avaxEVMETH = 0xA17Dd3Cc59951b0ED78D3bC9f6Ee944fF53FD1f2;

    uint64 constant avaxChainId = 14767482510784806043;

    address public linkBaseSepolia = 0xCCAda501AC392DB699aA85432eabc03abe403f30;

    address public linkFujiEVM = 0xCCAda501AC392DB699aA85432eabc03abe403f30;

    function run() external {
        if (block.chainid == 11155111) {
            vm.startBroadcast();
            EdenPL(_EVPL).addDestinationChain(avaxChainId, linkFujiEVM);

            vm.stopBroadcast();
        }
    }
}
