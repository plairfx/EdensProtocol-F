## Eden's Protocol Contract Folder

Eden’s protocol is a cross-chain privacy protocol which allows user to send any amount and withdraw it from whereever they want.
When there are no funds from depositers the pool will use the vaults as liquidity which will fund the ongoing transactions without relying on the depositers, while this makes the protocol less private, users have the choice to withdraw or wait for other depositers.

## This smart contract repo exist of 3 main contract:

EdenPL.sol:
The Pool contract deployed on the Ethereum mainnet for every token (eth,link,) etc.. whenever an EVM chain wants to withdraw/deposit it will receive a message. This goes through Chainlink’s CCIP.
EdenEVM.sol:
 The EVM Variant of the pool contract, whenever a deposit/withdraw is made the contract will call the EdenPL contract that has the same token and insert and verify the proofs.

EdenVault.sol:
The vault deployed on every chain providing liquidity to the user when there are no available withdraw/deposits. This is deployed with every EdenPL or EdenEVM Pool!
Note:
This is a non audited code with known issues.
