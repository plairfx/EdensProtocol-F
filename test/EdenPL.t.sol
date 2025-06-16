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

contract EdenPLTest is Test {
    // ETH..
    EdenPL EPL;
    EdenEVM EVPL;
    Receiver receiver;

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
        vm.deal(bob, 100 ether);
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

    // Test Suite

    function test_CrossChainDepositAndWithdrawWorks() public {
        uint256 amount = 9 ether;
        uint256 feeAmount = 1 ether;
        uint256 balanceBeforeDeposit = alice.balance;

        (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);

        vm.startPrank(alice);
        EVPL.deposit{value: 10 ether}(commitment, amount, feeAmount);

        // asserts
        assertEq(address(EVPL).balance, amount + feeAmount);
        assertEq(balanceBeforeDeposit - (amount + feeAmount), alice.balance);

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

        EVPL.withdraw(pA, pB, pC, nullifierHash, address(alice), root, 0 ether, relayer, 9 ether);

        // the withdraw fails?

        assertEq(address(EVPL).balance, 1 ether);
        assertEq(balanceBeforeDeposit - feeAmount, alice.balance);
    }

    function test_UserCannotUsePublishedProofForTheirOwn() public {
        uint256 amount = 9 ether;
        uint256 feeAmount = 1 ether;
        uint256 balanceBeforeDeposit = alice.balance;

        (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);

        vm.startPrank(alice);
        EVPL.deposit{value: 10 ether}(commitment, amount, feeAmount);

        // asserts
        assertEq(address(EVPL).balance, amount + feeAmount);
        assertEq(balanceBeforeDeposit - (amount + feeAmount), alice.balance);
        // assertEq(feeAmount, feeReceiver.balance);

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

        EVPL.withdraw(pA, pB, pC, nullifierHash, address(alice), root, 0 ether, relayer, 9 ether);

        vm.startPrank(bob);

        vm.expectRevert();
        EPL.withdraw(pA, pB, pC, nullifierHash, address(bob), root, 0 ether, relayer, 9 ether);
        assertEq(bob.balance, 100 ether);
    }

    function test_depositWorksAndReverts() public {
        uint256 amount = 1 ether;
        (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);

        vm.startPrank(alice);
        EPL.deposit{value: 1 ether}(commitment, 1 ether, 0);

        vm.expectRevert("Commitment already submitted");
        EPL.deposit{value: 15 ether}(commitment, 5 ether, 0);

        address relayer = makeAddr("relayer");

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

        assertTrue(
            verifier.verifyProof(
                pA,
                pB,
                pC,
                [
                    uint256(root),
                    uint256(nullifierHash),
                    uint256(amount),
                    uint256(uint160(address(alice))),
                    uint256(uint160(relayer)),
                    uint256(0),
                    uint256(0)
                ]
            )
        );
        uint256 balanceBefore = alice.balance;
        uint256 balanceBeforeEPL = address(EPL).balance;
        EPL.withdraw(pA, pB, pC, nullifierHash, address(alice), root, 0, relayer, amount);

        assertEq(balanceBefore + 1 ether, (alice).balance);
        assertEq(0, balanceBeforeEPL - 1 ether);
    }

    function test_withdrawFailures() public {
        uint256 amount = 1 ether;
        (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);

        vm.startPrank(alice);
        EPL.deposit{value: 1 ether}(commitment, 1 ether, 0);

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

        assertTrue(
            verifier.verifyProof(
                pA,
                pB,
                pC,
                [
                    uint256(root),
                    uint256(nullifierHash),
                    uint256(amount),
                    uint256(uint160(address(alice))),
                    uint256(uint160(relayer)),
                    uint256(0),
                    uint256(0)
                ]
            )
        );
        uint256 balanceBefore = alice.balance;
        uint256 balanceBeforeEPL = address(EPL).balance;

        // revert when user wants to withdraw a bigger amount than expected.
        vm.expectRevert(EdenPL.InvalidProof.selector);
        EPL.withdraw(pA, pB, pC, nullifierHash, address(alice), root, 0, relayer, 10 ether);

        vm.expectRevert("Cannot find your merkle root");
        EPL.withdraw(pA, pB, pC, nullifierHash, address(alice), bytes32("0x"), 0, relayer, amount);

        EPL.withdraw(pA, pB, pC, nullifierHash, address(alice), root, 0, relayer, amount);

        assertEq(balanceBefore + 1 ether, (alice).balance);
        assertEq(0, balanceBeforeEPL - 1 ether);

        // revert when same note/proof is used again,
        vm.expectRevert("The note has been already spent");
        EPL.withdraw(pA, pB, pC, nullifierHash, address(alice), root, 0, relayer, amount);
    }

    function test_ERC20_DepositAndWithdrawWorks() public {
        uint256 balancePoolB = ERC20.balanceOf(address(EPLERC20));
        uint256 balanceAliceB = ERC20.balanceOf(address(alice));

        uint256 amount = 1 ether;
        (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);

        vm.startPrank(alice);
        ERC20.approve(address(EPLERC20), 1 ether);
        EPLERC20.deposit(commitment, 1 ether, 0);

        assertEq(balancePoolB + 1 ether, ERC20.balanceOf(address(EPLERC20)));
        assertEq(balanceAliceB - 1 ether, ERC20.balanceOf(address(alice)));

        vm.expectRevert("Commitment already submitted");
        EPLERC20.deposit(commitment, 1 ether, 0);

        address relayer = makeAddr("relayer");

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

        uint256 balancePoolAfterD = ERC20.balanceOf(address(EPLERC20));
        uint256 balanceAliceAfterD = ERC20.balanceOf(address(alice));

        vm.expectRevert(EdenPL.InvalidProof.selector);
        EPLERC20.withdraw(pA, pB, pC, nullifierHash, address(alice), root, 0, relayer, amount + 10 ether);

        EPLERC20.withdraw(pA, pB, pC, nullifierHash, address(alice), root, 0, relayer, amount);

        assertEq(0, ERC20.balanceOf(address(EPLERC20)));

        assertEq(balanceAliceAfterD + amount, ERC20.balanceOf(address(alice)));
    }

    function test_onlyVaultDepositFeesERC20() public {
        vm.startPrank(alice);
        vm.expectRevert();
        EVMERC20.depositFees();

        vm.expectRevert();
        EPLERC20.depositFees();

        // Setting vault can only be done by owner (msg.sender) in this case.
        vm.startPrank(alice);
        vm.expectRevert();
        EVMERC20.setVault(address(alice));

        vm.expectRevert();
        EPLERC20.setVault(address(alice));

        // EPL- ERC20 Contract
        uint256 balancePoolB = ERC20.balanceOf(address(EPLERC20));
        uint256 balanceAliceB = ERC20.balanceOf(address(alice));

        uint256 amount = 5 ether;
        (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);

        vm.startPrank(alice);
        ERC20.approve(address(EPLERC20), 6 ether);
        EPLERC20.deposit(commitment, 5 ether, 1 ether);

        assertEq(balancePoolB + 6 ether, ERC20.balanceOf(address(EPLERC20)));
        assertEq(balanceAliceB - 6 ether, ERC20.balanceOf(address(alice)));

        // above here should be good.

        ERC20.approve(address(EdenERC), 1 ether);
        EdenERC.deposit(1 ether, 10);

        assertEq(balancePoolB + 5 ether, ERC20.balanceOf(address(EPLERC20)));

        assertEq(2 ether, ERC20.balanceOf(address(EdenERC)));

        // Lets now test the EVMERC20 contract.

        assertEq(EVMERC20.getVault(), address(EdenERCEVM));

        vm.startPrank(alice);

        uint256 balancePoolBEPL = ERC20.balanceOf(address(EVMERC20));
        uint256 balanceAliceBEPL = ERC20.balanceOf(address(alice));

        uint256 amount2 = 4 ether;
        (bytes32 commitment2, bytes32 nullifier2, bytes32 amountie2, bytes32 secret2) = _getCommitment(amount2);

        ERC20.approve(address(EVMERC20), 5 ether);
        EVMERC20.deposit(commitment2, 4 ether, 1 ether);
        assertEq(balancePoolBEPL + 5 ether, ERC20.balanceOf(address(EVMERC20)));

        ERC20.approve(address(EdenERCEVM), 1 ether);
        EdenERCEVM.deposit(1 ether, 10);

        assertEq(balancePoolBEPL + 4 ether, ERC20.balanceOf(address(EVMERC20)));

        assertEq(2 ether, ERC20.balanceOf(address(EdenERCEVM)));
    }

    function test_onlyVaultDepositFeesETH() public {
        // only vault can call
        vm.startPrank(alice);
        vm.expectRevert();
        EPL.depositFees();

        vm.expectRevert();
        EVPL.depositFees();

        vm.startPrank(alice);
        vm.expectRevert();
        EPL.setVault(address(alice));

        vm.expectRevert();
        EVPL.setVault(address(alice));

        assertEq(EPL.getVault(), address(EdenETH));

        // now lets start the prank, almost the same as the other

        uint256 amount = 5 ether;
        uint256 fee = 1 ether;
        (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);

        uint256 balanceBeforeDeposit = address(alice).balance;
        uint256 balanceFeeVaultBeforeDeposit = address(EdenETH).balance;

        // now we deposit on the EdenETH

        vm.startPrank(alice);
        EPL.deposit{value: amount + fee}(commitment, amount, fee);

        assertEq(address(EPL).balance, amount + fee);
        assertEq(balanceBeforeDeposit - 6 ether, alice.balance);

        uint256 vaultDeposit = 1 ether;
        EdenETH.deposit{value: 1 ether}(1 ether, 10);

        assertEq(address(EPL).balance, amount);
        assertEq(balanceFeeVaultBeforeDeposit + fee + vaultDeposit, address(EdenETH).balance);

        // Eden EVM experience..

        uint256 balanceBeforeDeposit2 = address(alice).balance;
        uint256 balanceFeeVaultBeforeDeposit2 = address(EdenETHEVM).balance;

        uint256 amount2 = 4 ether;

        (bytes32 commitment2, bytes32 nullifier2, bytes32 amountie2, bytes32 secret2) = _getCommitment(amount2);

        EVPL.deposit{value: amount2 + fee}(commitment2, amount2, fee);

        assertEq(address(EVPL).balance, amount2 + fee);
        assertEq(balanceBeforeDeposit2 - 5 ether, alice.balance);
        assertEq(address(EdenETHEVM), EVPL.getVault());

        EdenETHEVM.deposit{value: 1 ether}(1 ether, 10);

        assertEq(address(EVPL).balance, amount2);
        assertEq(balanceFeeVaultBeforeDeposit2 + fee + vaultDeposit, address(EdenETHEVM).balance);
    }

    function test_onlyVaultAndOnlyRouter() public {
        vm.startPrank(alice);
        vm.expectRevert();
        EPL.depositFees();

        UserDW.Withdraw memory withdraw;
        bytes memory _payload = abi.encode(withdraw);

        vm.startPrank(address(EdenETH));
        EPL.depositFees();

        vm.startPrank(alice);
        Client.Any2EVMMessage memory structie;

        vm.expectRevert();
        EPL.ccipReceive(structie);
    }

    function test_SameCommitmentReverts() public {
        uint256 amount = 5 ether;
        uint256 fee = 1 ether;
        (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);

        uint256 balanceBeforeDeposit = address(alice).balance;
        uint256 balanceFeeVaultBeforeDeposit = address(EdenETH).balance;

        // now we deposit on the EdenETH

        vm.startPrank(alice);
        vm.expectRevert();
        EPL.deposit{value: amount + fee}(commitment, 4 ether, fee);

        EPL.deposit{value: amount + fee}(commitment, amount, fee);

        vm.startPrank(bob);
        vm.expectRevert("Commitment already submitted");
        EPL.deposit{value: amount + fee}(commitment, amount, fee);
    }

    function test_notKnownRootWithWithdrawReverts() public {
        uint256 amount = 1 ether;
        (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);

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
        vm.startPrank(alice);
        vm.expectRevert("Cannot find your merkle root");

        EPL.withdraw(pA, pB, pC, nullifierHash, address(alice), bytes32(0x0), 0, relayer, amount);
    }

    // function test_withdrawFailsForContractWithNoReceive() public {
    //     uint256 amount = 1 ether;
    //     (bytes32 commitment, bytes32 nullifier, bytes32 amountie, bytes32 secret) = _getCommitment(amount);

    //     vm.startPrank(alice);
    //     EPL.deposit{value: 1 ether}(commitment, 1 ether, 0);

    //     bytes32[] memory leaves = new bytes32[](1);
    //     leaves[0] = commitment;

    //     (
    //         uint256[2] memory pA,
    //         uint256[2][2] memory pB,
    //         uint256[2] memory pC,
    //         bytes32 root,
    //         bytes32 nullifierHash,
    //         bytes32 amountiee
    //     ) = _getWitnessAndProof(nullifier, secret, bytes32(amountie), address(receiver), relayer, leaves);

    //     assertTrue(
    //         verifier.verifyProof(
    //             pA,
    //             pB,
    //             pC,
    //             [
    //                 uint256(root),
    //                 uint256(nullifierHash),
    //                 uint256(amount),
    //                 uint256(uint160(address(receiver))),
    //                 uint256(uint160(relayer)),
    //                 uint256(0),
    //                 uint256(0)
    //             ]
    //         )
    //     );
    //     uint256 balanceBefore = alice.balance;
    //     uint256 balanceBeforeEPL = address(EPL).balance;

    //     vm.startPrank(address(receiver));
    //     vm.expectRevert();
    //     EPL.withdraw(pA, pB, pC, nullifierHash, address(receiver), root, 0, relayer, amount);
    // }
}

contract Receiver {}
