//SPDX-License-Identifier: MIT

import {EdenPL, IHasher, IVerifier, UserDW} from "../src/EdenPL.sol";
import {EdenEVM} from "../src/EdenEVM.sol";
import {Test} from "forge-std/Test.sol";
import {Groth16Verifier} from "../src/verifier.sol";
import {console} from "forge-std/console.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {EdenVault} from "../src/EdenVault.sol";
import {
    CCIPLocalSimulator,
    IRouterClient,
    LinkToken,
    BurnMintERC677Helper
} from "@chainlink-local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "lib/chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

pragma solidity ^0.8.23;

contract EdenEVMTest is Test {
    // ETH..
    EdenPL EPL;
    EdenEVM EVPL;

    IRouterClient router;

    // ERC
    EdenPL EPLERC20;
    EdenEVM EVMERC20;

    Groth16Verifier verifier;

    ERC20Mock ERC20;

    // Vaults/LP Pools.
    EdenVault EdenETH;
    EdenVault EdenETHEVM;
    EdenVault EdenERC;
    EdenVault EdenERCEVM;

    // Bridge
    CCIPLocalSimulator CCIP;

    address alice = makeAddr("alice");
    address public mimcHasher;
    address endpoint = makeAddr("alice");
    address bob = makeAddr("bob");
    address relayer = makeAddr("relayer");

    function setUp() external {
        // Deploy MimcSponge hasher contract.
        // from nkrishang/tornado-cash-rebuilt repo.
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

        // Deploy the verifier made with snarkjs.
        verifier = new Groth16Verifier();

        // Deploy CCIP Simulator
        CCIP = new CCIPLocalSimulator();

        (
            uint64 chainSelector,
            IRouterClient sourceRouter,
            IRouterClient destinationRouter,
            ,
            LinkToken link,
            BurnMintERC677Helper ccipBnM,
        ) = CCIP.configuration();

        // Deploy ERC20Mock & Mint tokens & ETH
        ERC20 = new ERC20Mock();
        ERC20.mint(alice, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 1 ether);
        ERC20.mint(bob, 100 ether);

        // Private ETH pools

        EPL = new EdenPL(IVerifier(address(verifier)), IHasher(mimcHasher), address(0x0), 20, (address(sourceRouter)));

        EVPL = new EdenEVM(address(0x0), address(destinationRouter), chainSelector, address(EPL));

        EPL.addDestinationChain(chainSelector, address(EVPL));

        // Private ERC20 pools

        EPLERC20 =
            new EdenPL(IVerifier(address(verifier)), IHasher(mimcHasher), address(ERC20), 20, (address(sourceRouter)));

        EVMERC20 = new EdenEVM(address(ERC20), address(destinationRouter), chainSelector, address(EPLERC20));

        EPLERC20.addDestinationChain(chainSelector, address(EVMERC20));

        // Vaults ERC20's

        EdenERC = new EdenVault(address(ERC20), address(EPLERC20));
        EdenERCEVM = new EdenVault(address(ERC20), address(EVMERC20));

        // ERC Vaults (ETH MAINNET)
        EdenETH = new EdenVault(address(0x0), address(EPL));
        EdenETHEVM = new EdenVault(address(0x0), address(EVPL));

        // settings vaults ..

        /// ETH VAULTS
        EPL.setVault(address(EdenETH));
        EVPL.setVault(address(EdenETHEVM));

        /// ERC Vaults
        EVMERC20.setVault(address(EdenERCEVM));
        EPLERC20.setVault(address(EdenERC));
        vm.deal(address(sourceRouter), 100 ether); // Fund source router
        vm.deal(address(destinationRouter), 100 ether); // Fund destination router
    }

    function test_RouterWorksNicely() public {
        uint256 amount = 1 ether;

        uint256 aliceBalanceStart = alice.balance;
        console.log(EPL.getRouter(), EVPL.getRouter());
        vm.deal(address(EVPL), 100 ether);
        vm.deal(address(EPL), 100 ether);
        vm.startPrank(alice);
        (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);
        EPL.deposit{value: 1 ether}(commitment, amount, 0);

        assertEq(aliceBalanceStart - 1 ether, alice.balance);

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = commitment;

        (
            uint256[2] memory pA,
            uint256[2][2] memory pB,
            uint256[2] memory pC,
            bytes32 root,
            bytes32 nullifierHash,
            bytes32 amountiee
        ) = _getWitnessAndProof(nullifier, secret, bytes32(amountie), address(alice), relayer, leaves);

        EVPL.withdraw(pA, pB, pC, nullifierHash, address(alice), root, 0 ether, relayer, amount);

        assertEq(aliceBalanceStart, alice.balance);
    }

    function test_msgvalueCannotBeLessThanAmountPlusFee() public {
        vm.startPrank(alice);
        vm.expectRevert();
        EVPL.deposit{value: 1 ether}(bytes32("0x"), 10 ether, 1 ether);
    }

    function _getWitnessAndProof(
        bytes32 _nullifier,
        bytes32 _secret,
        bytes32 amount,
        address _recipient,
        address _relayer,
        bytes32[] memory leaves
    ) internal returns (uint256[2] memory, uint256[2][2] memory, uint256[2] memory, bytes32, bytes32, bytes32) {
        string[] memory inputs = new string[](9 + leaves.length);
        inputs[0] = "node";
        inputs[1] = "forge-ffi-scripts/generate_witness.js";

        inputs[2] = vm.toString(_nullifier);
        inputs[3] = vm.toString(_secret);
        inputs[4] = vm.toString(amount);
        inputs[5] = vm.toString(_recipient);
        inputs[6] = vm.toString(_relayer);
        inputs[7] = "0"; // Fee
        inputs[8] = "0"; // Refund

        // Start leaves at index 9 to avoid overwriting previous inputs
        for (uint256 i = 0; i < leaves.length; i++) {
            inputs[9 + i] = vm.toString(leaves[i]);
        }

        bytes memory result = vm.ffi(inputs);
        (
            uint256[2] memory pA,
            uint256[2][2] memory pB,
            uint256[2] memory pC,
            bytes32 root,
            bytes32 nullifierHash,
            bytes32 amount
        ) = abi.decode(result, (uint256[2], uint256[2][2], uint256[2], bytes32, bytes32, bytes32));

        return (pA, pB, pC, root, nullifierHash, amount);
    }

    function _getCommitment(uint256 amount)
        internal
        returns (bytes32 commitment, bytes32 nullifier, bytes32 amounte, bytes32 secret)
    {
        bytes32 amountie = bytes32(amount);
        string[] memory inputs = new string[](3);
        inputs[0] = "node";

        inputs[1] = "forge-ffi-scripts/generateCommitment.js";

        inputs[2] = vm.toString(amountie);

        bytes memory result = vm.ffi(inputs);
        (commitment, nullifier, amounte, secret) = abi.decode(result, (bytes32, bytes32, bytes32, bytes32));

        return (commitment, nullifier, amounte, secret);
    }

    // function test_depositRefundRevertsIfWalletsHasNoFunds() public {
    //     console.log(address(ERC20));
    //     vm.deal(address(EPLERC20), 5 ether);
    //     vm.deal(address(EVMERC20), 5 ether);
    //     vm.deal(address(alice), 15 ether);
    //     vm.deal(address(bob), 15 ether);

    //     uint256 amount = 9 ether;
    //     uint256 feeAmount = 1 ether;
    //     uint256 balanceBeforeDeposit = ERC20.balanceOf(alice);

    //     (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);

    //     vm.startPrank(alice);
    //     EVPL.deposit{value: 10 ether}(commitment, amount, feeAmount);

    //     uint256 balanceBeforeDepositBob = bob.balance;

    //     vm.startPrank(bob);

    //     EVPL.deposit{value: 10 ether}(commitment, amount, feeAmount);

    //     vm.startPrank(address(EVPL));
    //     address(alice).call{value: (address(EVPL).balance - 1 ether)}("");

    //     assertEq(balanceBeforeDepositBob - 10 ether, bob.balance);
    // }

    function test_IfCrossChainRefundsIfCommitmentAlreadyUsed() public {
        console.log(address(ERC20));
        vm.deal(address(EPLERC20), 5 ether);
        vm.deal(address(EVMERC20), 5 ether);
        vm.deal(address(alice), 5 ether);

        uint256 amount = 9 ether;
        uint256 feeAmount = 1 ether;
        uint256 balanceBeforeDeposit = ERC20.balanceOf(alice);

        (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);

        vm.startPrank(alice);
        ERC20.approve(address(EVMERC20), 10 ether);
        EVMERC20.deposit(commitment, amount, feeAmount);

        uint256 balanceBeforeDepositBob = ERC20.balanceOf(bob);

        vm.startPrank(bob);
        ERC20.approve(address(EVMERC20), 10 ether);
        EVMERC20.deposit(commitment, amount, feeAmount);

        assertEq(ERC20.balanceOf(bob), balanceBeforeDepositBob);
    }

    //
    function test_crossChainERC20DepositWithdrawWorks() public {
        console.log(address(ERC20));
        vm.deal(address(EPLERC20), 5 ether);
        vm.deal(address(EVMERC20), 5 ether);
        vm.deal(address(alice), 5 ether);

        uint256 amount = 9 ether;
        uint256 feeAmount = 1 ether;
        uint256 balanceBeforeDeposit = ERC20.balanceOf(alice);

        (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);

        vm.startPrank(alice);
        ERC20.approve(address(EVMERC20), 10 ether);
        EVMERC20.deposit(commitment, amount, feeAmount);

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = commitment;

        (
            uint256[2] memory pA,
            uint256[2][2] memory pB,
            uint256[2] memory pC,
            bytes32 root,
            bytes32 nullifierHash,
            bytes32 amountiee
        ) = _getWitnessAndProof(nullifier, secret, bytes32(amountie), address(alice), relayer, leaves);

        EVMERC20.withdraw(pA, pB, pC, nullifierHash, address(alice), root, 0 ether, relayer, 9 ether);

        assertEq(balanceBeforeDeposit - 1 ether, ERC20.balanceOf(alice));

        assertEq(EVMERC20.getFeesAccumulated(), 1 ether);
    }

    // function test_crossChainDepositsETHAnWithdrawsWorks() {
    //     console.log(address(ERC20));
    //     vm.deal(address(EVPL), 5 ether);
    //     vm.deal(address(EPL), 5 ether);
    //     vm.deal(address(alice), 5 ether);

    //     uint256 amount = 9 ether;
    //     uint256 feeAmount = 1 ether;
    //     uint256 balanceBeforeDeposit = ERC20.balanceOf(alice);

    //     (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);

    //     vm.startPrank(alice);

    //     EVMERC20.deposit(commitment, amount, feeAmount);

    //     bytes32[] memory leaves = new bytes32[](1);
    //     leaves[0] = commitment;

    //     (
    //         uint256[2] memory pA,
    //         uint256[2][2] memory pB,
    //         uint256[2] memory pC,
    //         bytes32 root,
    //         bytes32 nullifierHash,
    //         bytes32 amountiee
    //     ) = _getWitnessAndProof(nullifier, secret, bytes32(amountie), address(alice), relayer, leaves);

    //     EVMERC20.withdraw(pA, pB, pC, nullifierHash, address(alice), root, 0 ether, relayer, 9 ether);

    //     assertEq(EVMERC20.getFeesAccumulated(), 1 ether);
    // }

    function test_When_CrossChainCommitmentsISAlreadyUsedUserGetsRefund() public {
        console.log(address(ERC20));
        vm.deal(address(EPLERC20), 5 ether);
        vm.deal(address(EVMERC20), 5 ether);
        vm.deal(address(alice), 15 ether);
        vm.deal(address(bob), 15 ether);

        uint256 amount = 9 ether;
        uint256 feeAmount = 1 ether;
        uint256 balanceBeforeDeposit = ERC20.balanceOf(alice);

        (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);

        vm.startPrank(alice);
        EVPL.deposit{value: 10 ether}(commitment, amount, feeAmount);

        uint256 balanceBeforeDepositBob = bob.balance;

        vm.startPrank(bob);

        EVPL.deposit{value: 10 ether}(commitment, amount, feeAmount);

        assertEq(balanceBeforeDepositBob, bob.balance);
    }

    function test_onlyRouterCanCallEdenPools() public {
        vm.startPrank(alice);
        Client.Any2EVMMessage memory structie;

        vm.expectRevert();
        EVPL.ccipReceive(structie);
    }

    function test_onlyVaultCanCallDepositFees() public {
        vm.startPrank(alice);
        vm.expectRevert();
        EVPL.depositFees();

        vm.startPrank(address(EdenETHEVM));
        EVPL.depositFees();
    }

    function test_getAssetWorks() public {
        address ETH = EVPL.getAsset();
        address TOKEN = EPLERC20.getAsset();

        assertEq(ETH, address(0x0));
        assertEq(TOKEN, address(ERC20));
    }

    function test_ERC20GetsWithdrawnFine() public {}
}
