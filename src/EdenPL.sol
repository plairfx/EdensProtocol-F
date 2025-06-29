// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MerkleTreeWithHistory, IHasher} from "src/MerkleTreeWithHistory.sol";
import {IVerifier} from "./Interfaces/IVerifier.sol";
import {UserDW} from "./library/UserDW.sol";
import {IEdenVault} from "./Interfaces/IEdenVault.sol";
import {CCIPReceiver} from "lib/chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IRouterClient} from "lib/chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "lib/chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

contract EdenPL is CCIPReceiver, Ownable, MerkleTreeWithHistory, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IVerifier public immutable verifier;

    error InvalidProof();
    error UninitializedChain();

    address asset;
    address immutable i_router;
    address vault;
    uint256 feeAccumulated;

    mapping(uint64 => address) public s_destAddress;
    mapping(bytes32 => bool) public nullifierHashes;
    mapping(bytes32 hashie => bool) public commitments;

    event Deposited(bytes32 commitment, uint256 amount, uint256 index, uint64 chain, bytes32 MessageId, address _asset);
    event Withdrawn(address receiver, uint256 amount, uint64 chain, bytes32 MessageId, address _asset);
    event DepositFailed(address refundReceiver, uint256 amount, bytes32 MessageID);
    event WithdrawFailed(address receiver, uint256 amount, bytes32 MessageID);

    modifier onlyVault() {
        require(msg.sender == vault);
        _;
    }

    /**
     * @param _verifier the verifier for the merkleProofs.
     * @param _hasher the hasher for the merkleTree.
     * @param _asset if asset is set as 0x0 address the pool will only accept ETH, vice versa if its sets as a token
     * @param merkleTreeHeight  the set height of the merkleTree
     * @param _router from @chainlink on the specific EVM-Chain.
     */
    constructor(IVerifier _verifier, IHasher _hasher, address _asset, uint32 merkleTreeHeight, address _router)
        MerkleTreeWithHistory(merkleTreeHeight, _hasher)
        CCIPReceiver(_router)
    {
        // sets the verifier & hasher.
        verifier = _verifier;
        asset = _asset;
        i_router = _router;
    }

    receive() external payable {}

    /**
     * @notice deposits token into the pool
     * @param _commitment The generated commitment, cannot be used twice.
     * @param amount The amount to deposit
     * @param fee The fee the user pays for the front-end.
     * @return index
     */
    function deposit(bytes32 _commitment, uint256 amount, uint256 fee)
        external
        payable
        nonReentrant
        returns (uint256 index)
    {
        require(!commitments[_commitment], "Commitment already submitted");
        require(amount > 0);

        uint256 index = _insert(_commitment);

        commitments[_commitment] = true;

        if (asset != address(0x0)) {
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount + fee);
            feeAccumulated += fee;
        } else {
            require(msg.value >= amount + fee);

            feeAccumulated += fee;
        }

        emit Deposited(_commitment, amount, index, 0, bytes32(0), asset);
    }

    /**
     * @notice withdraws tokens from the pool
     * @param _pA,_pB and _pC  are parts of the ZK-Proof.
     * @param nullifierHash test
     * @param receiver the wallet/contract which will receive the token
     * @param root the root of the tree where the proof got deposited in.
     * @param fee the fee the user gives to the pool (Frontend has a fee).
     * @param relayer the relayer the user wants to use (not avaliable at this moment).
     * @param amount the amount the user wants to withdraw.
     */
    function withdraw(
        uint256[2] calldata _pA,
        uint256[2][2] calldata _pB,
        uint256[2] calldata _pC,
        bytes32 nullifierHash,
        address receiver,
        bytes32 root,
        uint256 fee,
        address relayer,
        uint256 amount
    ) external payable nonReentrant {
        require(!nullifierHashes[nullifierHash], "The note has been already spent");
        require(isKnownRoot(root), "Cannot find your merkle root");
        require(
            verifier.verifyProof(
                _pA,
                _pB,
                _pC,
                [
                    uint256(root),
                    uint256(nullifierHash),
                    uint256(amount),
                    uint256(uint160(address(receiver))),
                    uint256(uint160(relayer)),
                    fee,
                    uint256(0)
                ]
            ),
            InvalidProof()
        );

        nullifierHashes[nullifierHash] = true;

        _withdraw(amount, receiver, fee);

        emit Withdrawn(receiver, amount, 0, bytes32(0), asset);
    }

    // /**
    //  * @notice receives the messages send by CCIP, to confirm/deny deposits and withdraws.
    //  * @dev when it receives a message from EdenEVM, it will confirm if the deposit is correct,
    //  * or if the proof/root/nullifierHash is not used for the withdraw.
    //  */

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        UserDW.Withdraw memory withdrawS = abi.decode(message.data, (UserDW.Withdraw));

        if (withdrawS.withdraw) {
            _edWithdraw(withdrawS, message.sourceChainSelector);
        } else {
            _edDeposit(withdrawS, message.sourceChainSelector);
        }
    }

    function _send(uint64 destinationChainSelector, address receiver, bytes memory _data)
        internal
        returns (bytes32 messageId)
    {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: _data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 1_000_000, allowOutOfOrderExecution: true})),
            feeToken: address(0)
        });

        uint256 fee = IRouterClient(i_router).getFee(destinationChainSelector, message);

        messageId = IRouterClient(i_router).ccipSend{value: fee}(destinationChainSelector, message);

        // emit MessageSent(messageId);
    }

    /**
     * @notice The 'LPVault' called by the vault to receive the feesAccumulated by this Pool.
     * @dev  This depositFees can only be called by a vault set with `setVault`.
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
        } else {}
    }

    /**
     * @notice sets the Vault linked to this address.
     */
    function setVault(address _vault) public onlyOwner {
        vault = _vault;
    }

    /**
     * @notice adds an EVM chain to the possible destinations to  accept withdraws/deposits from.
     */
    function addDestinationChain(uint64 _destinationChain, address dest_address) public onlyOwner {
        s_destAddress[_destinationChain] = dest_address;
    }

    function _checkDestinationDomain(uint64 _destinationChain) internal returns (address, bool) {
        address destAddress = s_destAddress[_destinationChain];
        require(destAddress != address(0), "Destination address not registered");
        return (destAddress, true);
    }

    function _withdraw(uint256 amount, address receiver, uint256 fee) internal returns (uint256 withdrawnAmount) {
        if (amount > getTotalBalance()) {
            IEdenVault(vault).useLiq(amount);
        }
        if (asset != address(0x0)) {
            IERC20(asset).safeTransfer(receiver, amount);
            feeAccumulated += fee;
        } else {
            (bool success2,) = receiver.call{value: amount}("");
            require(success2);
            feeAccumulated += fee;
        }
    }

    /**
     * @notice handles the deposit from an EVM chain.
     * @dev if the commitment has not been used/ destinatition is a valid path
     * it will return a valid message, else it will return a invalid message.
     */
    function _edDeposit(UserDW.Withdraw memory withdraw, uint64 orgChain) internal returns (uint256 index) {
        (address _destinationAddress, bool valid) = _checkDestinationDomain(orgChain);
        require(_destinationAddress == withdraw.senderPool, "Wrong destAddr");
        if (_destinationAddress == address(0x0) || commitments[withdraw.commitment]) {
            withdraw.depositW = false;

            bytes memory _payload = abi.encode(withdraw);

            bytes32 _messageId = _send(orgChain, _destinationAddress, _payload);

            emit DepositFailed(withdraw.receiver, withdraw.amount, _messageId);
        } else {
            uint256 index = _insert(withdraw.commitment);

            commitments[withdraw.commitment] = true;

            withdraw.depositW = true;

            bytes memory _payload = abi.encode(withdraw);

            bytes32 _messageId = _send(orgChain, _destinationAddress, _payload);

            emit Deposited(withdraw.commitment, withdraw.amount, index, orgChain, _messageId, asset);
        }
    }

    /**
     * @notice handles the withdraw from an EVM chain.
     * @dev if the proof/root/desitination address is correct,
     * it will return a valid message, else it will return a invalid message.
     */
    function _edWithdraw(UserDW.Withdraw memory withdraw, uint64 orgChain) internal returns (bool) {
        (address _destinationAddress, bool valid) = _checkDestinationDomain(orgChain);
        require(_destinationAddress == withdraw.senderPool, "Wrong destAddr");
        if (
            nullifierHashes[withdraw.nullifierHash] || !isKnownRoot(withdraw.root)
                || !verifier.verifyProof(
                    withdraw.pA,
                    withdraw.pB,
                    withdraw.pC,
                    [
                        uint256(withdraw.root),
                        uint256(withdraw.nullifierHash),
                        uint256(withdraw.amount),
                        uint256(uint160(address(withdraw.receiver))),
                        uint256(uint160(withdraw.relayer)),
                        withdraw.fee,
                        uint256(0)
                    ]
                ) || _destinationAddress == address(0x0)
        ) {
            withdraw.withdraw = true;
            withdraw.depositW = false;

            bytes memory _payload = abi.encode(withdraw);

            bytes32 messageID = _send(orgChain, _destinationAddress, _payload);

            emit WithdrawFailed(withdraw.receiver, withdraw.amount, messageID);
        } else {
            nullifierHashes[withdraw.nullifierHash] = true;

            withdraw.withdraw = true;
            withdraw.depositW = true;

            bytes memory _payload = abi.encode(withdraw);

            bytes32 _messageId = _send(orgChain, _destinationAddress, _payload);

            emit Withdrawn(withdraw.receiver, withdraw.amount, orgChain, _messageId, asset);
        }
    }

    /**
     * @notice returns the asset address.
     * address(0x0) means native token!
     */
    function getAsset() public view returns (address) {
        return asset;
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
