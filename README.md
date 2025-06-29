# Eden's Protocol Contract Folder

Eden’s protocol is a cross-chain privacy protocol which allows user to send any amount and withdraw it from where ever they want, this protocol is heavily inspired by Tornado-Cash,

The vision was to make Eden's Protocol a cross-chain privacy bridge, which allows user to deposit and withdraw from every EVM chain, and even if there are no deposits the vault liquidity can be used still let it function as a bridge.

## How does it work?

Whenever a user deposits it will create a deposit proof for the user to withdraw with
If the amount that the user wants to withdraw with is not equal the one he deposited, the verification of the proof will fail.

The user can withdraw and deposit on multiple evm chains:
- Ethereum
- Avalanche
- Base

If he deposits or withdraws on a non-evm chain, he will send a CCIP message ([EdenEVM.sol](https://github.com/plairfx/EdensProtocol-F/blob/main/src/EdenEVM.sol)) with the commitment or proof, if this for the user fails the user gets his deposit money back.

The mainnet Pool [(EdenPL.soL)](https://github.com/plairfx/EdensProtocol-F/blob/main/src/EdenPL.sol) will send a message with CCIP back with the results, if the withdrwaw is successfull the user will receive his deposit-amount, if it fails a withdrawFailed or depositFailed event will be emitted.

![image](https://github.com/user-attachments/assets/86b216b0-730e-4c34-8d8d-4999f7c84e92)

## This smart contract repo exist of 3 main contract:

### **[EdenPL.sol](https://github.com/plairfx/EdensProtocol-F/blob/main/src/EdenPL.sol):**
The Pool contract deployed on the Ethereum mainnet for every token (eth,link,) etc.. whenever an EVM chain wants to withdraw/deposit it will receive a message. This goes through Chainlink’s CCIP.

### **[EdenEVM.sol](https://github.com/plairfx/EdensProtocol-F/blob/main/src/EdenEVM.sol):**
 The EVM Variant of the pool contract, whenever a deposit/withdraw is made the contract will call the EdenPL contract that has the same token and insert and verify the proofs.

### **EdenVault.sol**:
The vault deployed on every chain providing liquidity to the user when there are no available withdraw/deposits. This is deployed with every EdenPL or EdenEVM Pool!

### **verifier.sol**:
The contract used to verify the proofs onchain.

## **MerkleTreeWitHistory**:
The merkle tree used to make the storing commitments and help verify the withdraws.


![image](https://github.com/user-attachments/assets/8d428ce4-631d-4bef-ab73-2179670966ac)


Note:
This is a non audited code with known issues.


## Eden's Frontend repo:

https://github.com/plairfx/EdensProtocolFrontend

Frontend link: finaledenp.vercel.app


Resources used to make this project a success
