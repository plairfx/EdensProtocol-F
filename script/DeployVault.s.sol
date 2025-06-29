// SPDX-License-Identifier: MIT

import {Script} from "forge-std/Script.sol";
import {EdenPL, IHasher, IVerifier, UserDW} from "../src/EdenPL.sol";
import {EdenEVM} from "../src/EdenEVM.sol";
import {Groth16Verifier} from "../src/verifier.sol";
import {EdenVault} from "../src/EdenVault.sol";

pragma solidity ^0.8.23;

contract DeployVault is Script {
    EdenPL public EPL;
    EdenEVM public EVPL;
    EdenVault public EVT;
    EdenVault public EVTL;

    // ETH POOLS:
    address payable EthSepoliaPool = payable(address(0x4418Ba6d81b2C3C031A969203d26A49bB8055d20));
    address payable EthbaseSepoliaPool = payable(address(0xA17Dd3Cc59951b0ED78D3bC9f6Ee944fF53FD1f2));
    address payable EthFujiPool = payable(address(0xA17Dd3Cc59951b0ED78D3bC9f6Ee944fF53FD1f2));

    // LINK POOLS:
    address payable linkSepoliaPool = payable(address(0xD90f34B559C7b964cb705c5cadaCb682950324f9));
    address payable baseSepoliaPool = payable(address(0xCCAda501AC392DB699aA85432eabc03abe403f30));
    address payable LinkFujiPool = payable(address(0xCCAda501AC392DB699aA85432eabc03abe403f30));

    // Link TOKENS
    address LinkTokenETHSepolia = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address LinkTokenBaseSepolia = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;
    address AvaxFujiLinkToken = 0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846;

    function run() external {
        if (block.chainid == 11155111) {
            vm.startBroadcast();

            // ETH VAULT FIRST
            EVT = new EdenVault(address(0x0), address(EthSepoliaPool));
            EVTL = new EdenVault(address(LinkTokenETHSepolia), address(linkSepoliaPool));

            EdenPL(EthSepoliaPool).setVault(address(EVT));
            EdenPL(linkSepoliaPool).setVault(address(EVTL));
        } else if (block.chainid == 84532) {
            vm.startBroadcast();

            EVT = new EdenVault(address(0x0), address(EthbaseSepoliaPool));
            EVTL = new EdenVault(address(LinkTokenBaseSepolia), address(baseSepoliaPool));

            EdenEVM(EthbaseSepoliaPool).setVault(address(EVT));
            EdenEVM(baseSepoliaPool).setVault(address(EVTL));

            vm.stopBroadcast();
        } else {
            vm.startBroadcast();

            EVT = new EdenVault(address(0x0), address(EthFujiPool));
            EVTL = new EdenVault(address(AvaxFujiLinkToken), address(LinkFujiPool));

            EdenEVM(EthFujiPool).setVault(address(EVT));
            EdenEVM(LinkFujiPool).setVault(address(EVTL));

            vm.stopBroadcast();
        }
    }
}
