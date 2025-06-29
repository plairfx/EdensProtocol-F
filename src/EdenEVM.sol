// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UserDW} from "./library/UserDW.sol";
import {IEdenVault} from "./Interfaces/IEdenVault.sol";
import {CCIPReceiver} from "lib/chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";

import {IRouterClient} from "lib/chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "lib/chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

contract EdenEVM is CCIPReceiver, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint64 immutable i_destChain;
    address immutable i_router;
    address immutable i_destAddress;
    address asset;
    uint256 feeAccumulated;
    address vault;

    modifier onlyVault() {
        require(msg.sender == vault);
        _;
    }

    /**
     * @param _asset if asset is set as 0x0 address the pool will only accept ETH, vice versa if its sets as a token.
     * @param _router router from @chainlink on the specific EVM-Chain.
     * @param _destChain destinationId of the mainchain (ETH).
     * @param _destAddr address of the mainpool ETH (EdenPL.sol).
     */
    constructor(address _asset, address _router, uint64 _destChain, address _destAddr) CCIPReceiver(_router) {
        asset = _asset;
        i_router = _router;
        i_destAddress = _destAddr;
        i_destChain = _destChain;
    }

    receive() external payable {}

    /**
     * @notice deposits token into the pool
     * @dev Deposits the token into the pool and sends a message via `Chainlink` to the ETH-Mainnet to confirm it
     * sends message to _deposit with confirmations.
     * @param _commitment The generated commitment, cannot be used twice.
     * @param amount The amount to deposit
     * @param fee The fee the user pays for the vault.
     * @return index
     */
    function deposit(bytes32 _commitment, uint256 amount, uint256 fee)
        external
        payable
        nonReentrant
        returns (uint256 index)
    {
        if (asset == address(0x0)) {
            require(msg.value >= amount + fee, "Msg.value should be equal/more then amount+fee");
        }
        require(amount > 0, "Amount should be more than 0");

        UserDW.Withdraw memory DE;
        DE.amount = amount;
        DE.commitment = _commitment;
        DE.receiver = msg.sender;
        DE.fee = fee;
        DE.senderPool = address(this);

        bytes memory _payload = abi.encode(DE);

        uint256 CCIPfee = getCCIPFee(_payload);
        if (asset != address(0x0)) {
            require(msg.value >= CCIPfee, "MSG.value should be equal to CCIpFee");
        } else {
            require(msg.value >= amount + CCIPfee, "msg.value should be more than amount and fee");
        }
        if (asset != address(0x0)) {
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount + fee);
        }

        _send(i_destChain, _payload);
    }

    /**
     * @notice withdraws tokens from the pool
     * @dev withdraws the tokens from the pool and sends a message via `Chainlink` to the ETH-Mainnet to confirm it
     * if the proof is true it will send the token & amount back to the user.
     * @param _pA ,_pB and _pC  are parts of the ZK-Proof.
     * @param _nullifierHash no hello
     * @param _receiver the wallet/contract which will receive the token
     * @param _root the root of the tree where the proof got deposited in.
     * @param _fee the fee the user gives to the pool (Frontend has a fee).
     * @param _relayer the relayer the user wants to use (not avaliable at this moment).
     * @param _amount the amount the user wants to withdraw.
     */
    function withdraw(
        uint256[2] calldata _pA,
        uint256[2][2] calldata _pB,
        uint256[2] calldata _pC,
        bytes32 _nullifierHash,
        address _receiver,
        bytes32 _root,
        uint256 _fee,
        address _relayer,
        uint256 _amount
    ) external payable nonReentrant {
        UserDW.Withdraw memory myStruct = UserDW.Withdraw({
            pA: _pA,
            pB: _pB,
            pC: _pC,
            nullifierHash: _nullifierHash,
            receiver: _receiver,
            root: _root,
            fee: _fee,
            relayer: _relayer,
            amount: _amount,
            withdraw: true,
            commitment: bytes32(0x0),
            depositW: false,
            senderPool: address(this)
        });

        bytes memory _payload = abi.encode(myStruct);

        _send(i_destChain, _payload);
    }

    function _send(uint64 destinationChainSelector, bytes memory _data) internal returns (bytes32 messageId) {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(i_destAddress),
            data: _data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 3_000_000, allowOutOfOrderExecution: true})),
            feeToken: address(0)
        });

        uint256 fee = IRouterClient(i_router).getFee(i_destChain, message);

        messageId = IRouterClient(i_router).ccipSend{value: fee}(destinationChainSelector, message);

        // emit MessageSent(messageId);
    }

    /**
     * @notice The 'LPVault' called by the vault to receive the feesAccumulated by this Pool.
     * @dev This depositFees can only be called by a vault set with `setVault`.
     */
    function depositFees() external onlyVault returns (uint256 feeAccum) {
        if (feeAccumulated > 0) {
            if (asset != address(0x0)) {
                IERC20(asset).safeTransfer(vault, feeAccumulated);

                feeAccum = feeAccumulated;

                // resetting
                feeAccumulated = 0;
            } else {
                (bool success,) = vault.call{value: feeAccumulated}("");
                require(success);
                feeAccum = feeAccumulated;

                // resetting
                feeAccumulated = 0;
            }
        }
    }

    /**
     * @notice sets the Vault linked to this address.
     */
    function setVault(address _vault) public onlyOwner {
        vault = _vault;
    }

    /**
     * @notice handles the withdraw message received from the main-chain.
     * @dev if the withdraw is correctly handled it will send the fees else emit WithdrawFailed` event.
     */
    // No scenario made where the contract could be empty.
    function _withdraw(uint256 amount, address receiver, uint256 fee, bool success)
        internal
        returns (uint256 withdrawnAmount)
    {
        if (success) {
            if (amount > getTotalBalance()) {
                IEdenVault(vault).useLiq(amount);
            }
            if (asset != address(0x0)) {
                IERC20(asset).safeTransfer(receiver, amount);
                feeAccumulated += fee;
            } else {
                (bool success2,) = receiver.call{value: amount - fee}("");
                require(success2);
                feeAccumulated += fee;
            }
        }
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        UserDW.Withdraw memory withdrawS = abi.decode(message.data, (UserDW.Withdraw));

        if (withdrawS.withdraw) {
            _withdraw(withdrawS.amount, withdrawS.receiver, withdrawS.fee, withdrawS.depositW);
        } else {
            _deposit(withdrawS.commitment, withdrawS.amount, withdrawS.fee, withdrawS.depositW, withdrawS.receiver);
        }
    }

    /**
     * @notice handles the deposit message received from the main-chain (_handle)
     * @dev if deposit is not successful it will send the amount back in ERC20 or ETH. (depending on the `asset`).
     */
    function _deposit(bytes32 _commitment, uint256 amount, uint256 fee, bool success, address receiver) internal {
        if (success) {
            feeAccumulated += fee;
        } else {
            if (asset == address(0x0)) {
                (bool success,) = receiver.call{value: amount + fee}("");
                require(success);
            } else {
                IERC20(asset).safeTransfer(receiver, amount + fee);
            }
        }
    }
    /**
     * @notice returns the asset address.
     * address(0x0) means native token!
     */

    function getAsset() public view returns (address) {
        return asset;
    }

    function getCCIPFee(bytes memory _data) public view returns (uint256 ccipFee) {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(i_destAddress),
            data: _data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 1_000_000, allowOutOfOrderExecution: true})),
            feeToken: address(0)
        });

        ccipFee = IRouterClient(i_router).getFee(i_destChain, message);
    }

    /**
     * @notice returns the `feeAccumulated`.
     */
    function getFeesAccumulated() public view returns (uint256) {
        return feeAccumulated;
    }

    /**
     * @notice returns the `totalBalance`.
     */
    function getTotalBalance() internal view returns (uint256) {
        if (asset != address(0x0)) {
            return IERC20(asset).balanceOf(address(this));
        } else {
            return address(this).balance;
        }
    }

    /**
     * @notice returns the vault address.
     */
    function getVault() public view returns (address) {
        return vault;
    }
}
