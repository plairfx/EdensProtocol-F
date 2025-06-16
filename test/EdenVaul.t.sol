// SPDX-License-Identifier: MIT

import {EdenVault} from "../src/EdenVault.sol";
import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {EdenPL, IHasher, IVerifier} from "../src/EdenPL.sol";
import {Groth16Verifier} from "../src/verifier.sol";
import {
    CCIPLocalSimulator,
    IRouterClient,
    LinkToken,
    BurnMintERC677Helper
} from "@chainlink-local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "lib/chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

pragma solidity ^0.8.23;

contract EdenVaultTest is Test {
    EdenVault EdenETH;
    EdenVault EdenERC;
    IRouterClient router;

    EdenPL EPL;
    ERC20Mock ERC;
    RevertPayment RP;
    Groth16Verifier verifier;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    CCIPLocalSimulator CCIP;

    function setUp() external {
        verifier = new Groth16Verifier();
        RP = new RevertPayment();
        ERC = new ERC20Mock();
        CCIP = new CCIPLocalSimulator();

        (
            uint64 chainSelector,
            IRouterClient sourceRouter,
            IRouterClient destinationRouter,
            ,
            LinkToken link,
            BurnMintERC677Helper ccipBnM,
        ) = CCIP.configuration();
        EPL = new EdenPL(IVerifier(address(verifier)), IHasher(address(0x0)), address(ERC), 20, address(sourceRouter));
        EdenETH = new EdenVault(address(0x0), address(EPL));
        EdenERC = new EdenVault(address(ERC), address(EPL));

        EPL.setVault(address(EdenETH));

        vm.deal(alice, 100 ether);
        ERC.mint(alice, 100 ether);

        vm.deal(bob, 100 ether);
        ERC.mint(bob, 100 ether);

        /// we want to make sure we make the first deposit, so there is no

        vm.deal(address(this), 100 ether);
        ERC.mint(address(this), 100 ether);

        // pool

        // depositing in both vaults..
        ERC.approve(address(EdenERC), 10 ether);
        uint256 shares1 = EdenERC.deposit(1 ether, 0.01 ether);
        uint256 shares = EdenETH.deposit{value: 1 ether}(1 ether, 0.01 ether);
        assertEq(shares, 1 ether);
        assertEq(shares1, 1 ether);
        // first deposit will always be equal to the first asset ammount
        // so if user deposits 1 ether he will receive 1 share etc..

        // deposits done..
    }

    function test_getFunctionsWork() public {
        assertEq(EdenERC.getAsset(), address(ERC));
        assertEq(EdenETH.getAsset(), address(0x0));

        assertEq(EdenETH.decimals(), 18);
        assertEq(EdenERC.decimals(), ERC.decimals());
    }

    function test_ReceiveOnlyWorksOnEth() public {
        vm.startPrank(alice);

        vm.expectRevert("Asset Not Eth");
        address(EdenERC).call{value: 1 ether}("");

        address(EdenETH).call{value: 1 ether}("");

        assertGt(EdenETH.balanceOf(alice), 0);
    }

    function test_DepositWorksForUser() public {
        vm.startPrank(alice);

        vm.expectRevert(EdenVault.AmountIsNotEqualDepositedETH.selector);

        EdenETH.deposit{value: 0.1 ether}(1 ether, 0.5 ether);

        uint256 totalSharesB = EdenERC.totalSupply();
        uint256 totalSharesBETH = EdenETH.totalSupply();

        uint256 aliceShareBalanceBeforeERC = EdenERC.balanceOf(alice);
        uint256 aliceShareBalanceBeforeETH = EdenETH.balanceOf(alice);

        // expected Deposts
        uint256 expectedDepositERC = EdenERC.convertToShares(1 ether);
        uint256 expectedDepositETH = EdenETH.convertToShares(1 ether);

        uint256 assetBalanceB = EdenERC.totalAssets();
        uint256 assetBalanceBETH = EdenETH.totalAssets();

        // EdenERC vault.
        ERC.approve(address(EdenERC), 1 ether);
        // deposit will revert if its less than expected amount.
        vm.expectRevert(EdenVault.SharesOrAssetsLessThanExpected.selector);

        EdenERC.deposit(1 ether, 10 ether);

        vm.expectEmit();
        emit EdenVault.Deposited(1 ether);

        EdenERC.deposit(1 ether, 0.5 ether);
        uint256 totalSharesAfter = EdenERC.totalSupply();

        // EdenEth Vault
        vm.expectEmit();
        emit EdenVault.Deposited(1 ether);
        EdenETH.deposit{value: 1 ether}(1 ether, 0.5 ether);

        uint256 aliceShareBalanceAfterERC = EdenERC.balanceOf(alice);
        uint256 aliceShareBalanceAfterETH = EdenETH.balanceOf(alice);
        uint256 totalsharesAfterETH = EdenETH.totalSupply();

        uint256 assetBalanceAfter = EdenERC.totalAssets();
        uint256 assetBalanceBethAfter = EdenETH.totalAssets();

        console.log(expectedDepositERC);

        assertEq(expectedDepositERC, EdenERC.balanceOf(alice));

        assertEq(expectedDepositETH, EdenETH.balanceOf(alice));

        assertGt(totalSharesAfter, totalSharesB);
        assertGt(totalsharesAfterETH, totalSharesBETH);
        assertGt(assetBalanceAfter, assetBalanceB);
        assertGt(assetBalanceBethAfter, assetBalanceBETH);
        assertGt(aliceShareBalanceAfterERC, aliceShareBalanceBeforeERC);
        assertGt(aliceShareBalanceAfterETH, aliceShareBalanceBeforeETH);
    }

    function test_withdrawWorks() public {
        // Depositing both vaults..
        vm.startPrank(alice);
        ERC.approve(address(EdenERC), 1 ether);
        EdenERC.deposit(1 ether, 0.01 ether);
        EdenETH.deposit{value: 1 ether}(1 ether, 0.5 ether);

        uint256 aliceBalanceBefore = ERC.balanceOf(alice);
        uint256 aliceBalanceBeforeETH = alice.balance;

        uint256 totalSharesAfter = EdenERC.totalSupply();
        uint256 totalsharesAfterETH = EdenETH.totalSupply();
        uint256 totalSharesAlice = EdenERC.balanceOf(alice);
        uint256 totalSharesAliceETH = EdenETH.balanceOf(alice);
        uint256 assetBalanceAfter = EdenERC.totalAssets();
        uint256 assetBalanceBethAfter = EdenETH.totalAssets();

        //
        uint256 expectedERC = EdenERC.convertToAssets(totalSharesAlice);
        uint256 expectedETH = EdenETH.convertToAssets(totalSharesAliceETH);

        // Withdrwaing..

        vm.expectRevert(EdenVault.SharesOrAssetsLessThanExpected.selector);
        // will revert if the shares are not as expected.
        EdenERC.withdraw(totalSharesAlice, 10 ether);

        vm.expectEmit();
        emit EdenVault.Withdrawn(1 ether);
        uint256 assetsa = EdenERC.withdraw(totalSharesAlice, 1 ether);
        assertEq(assetsa, 1 ether);

        vm.expectEmit();
        emit EdenVault.Withdrawn(1 ether);
        uint256 assets = EdenETH.withdraw(totalSharesAlice, 1 ether);
        assertEq(assets, 1 ether);

        assertEq(0, EdenERC.balanceOf(alice));
        assertEq(0, EdenETH.balanceOf(alice));

        // For at the moment it rounds of into favour of the protocol, which we will accept,
        assertEq(aliceBalanceBefore + expectedERC, ERC.balanceOf(alice));
        assertEq(aliceBalanceBeforeETH + expectedETH, alice.balance);

        assertEq(totalSharesAfter - totalSharesAlice, EdenERC.totalSupply());
        assertEq(totalsharesAfterETH - totalSharesAliceETH, EdenETH.totalSupply());
    }

    function test_ifWithdrawRevertsItWillFail() public {
        vm.deal(address(RP), 100 ether);
        vm.startPrank(address(RP));

        EdenETH.deposit{value: 10 ether}(10 ether, 1 ether);

        vm.expectRevert();
        EdenETH.withdraw(1 ether, 0.5 ether);
    }

    function test_useLiqSendsEthToPool() public {
        vm.startPrank(alice);

        // EdenERC vault.
        ERC.approve(address(EdenERC), 1 ether);

        vm.expectEmit();
        emit EdenVault.Deposited(1 ether);

        EdenERC.deposit(1 ether, 0.5 ether);
        uint256 totalSharesAfter = EdenERC.totalSupply();

        // EdenEth Vault
        vm.expectEmit();
        emit EdenVault.Deposited(1 ether);
        EdenETH.deposit{value: 1 ether}(1 ether, 0.5 ether);

        vm.expectRevert();
        EdenETH.useLiq(1 ether);

        assertEq(address(EPL).balance, 0 ether);

        vm.startPrank(address(EPL));
        EdenETH.useLiq(1 ether);
        assertEq(address(EPL).balance, 1 ether);

        assertEq(ERC.balanceOf(address(EPL)), 0 ether);
        EdenERC.useLiq(1 ether);

        uint256 balancePoolAfterERC = ERC.balanceOf(address(EPL));
        assertEq(ERC.balanceOf(address(EPL)), 1 ether);
    }
}

contract RevertPayment {
    receive() external payable {
        revert();
    }
}
