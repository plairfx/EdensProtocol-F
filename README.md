## EdenProtocol

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

A crosschain tornado-cash like protocol which allows user to bridge their funds privately whenever whatever amount they want/need.

Normally for privacy there is a set place and set amount the user needs to withdraw/deposit from but in this case that does not happen.

As the user can deposit and withdraw from every deployed chain,


# TO BE CONFIRMED:
We want the users to have an refined experience with Eden, so they have both the choice to transact privately or transact instantly to his destination, which will allow.
-??

This repo consists of 3 main contracts,
- EdenPL (Eden Privacy Pool (Launched only on ETH)).
- EdenEVM (Launched only EVM chains).
- EdenVault (Vault which users can provide LP to the pool.).


When an user deposits he expects to atleast get some privacy, at whatever amount the users demand, 0.01 ether deposits? 500 ether deposits? Who knows, the front-end will recocmmmend to the user the most used amount, but the decision stays with the user.


(This is a testnet protocol and is not live, this is meant to showcase the possibility of crosschain deposits).



# Concerns/Risks with this idea.
  
  * Issue: When an user withdraws from a pool, there is no rebalancer/ a way to get the vaults LP back without compromising on the user's privacy.
  Example:

  * Risks: MerkleTree can fill up much faster as all EVM pools are depended on writing in the ETH merkle-tree through HyperLane.
  * Concerns: If Hyperlane relayer decides not to deliver a message, the user deposit/withdraw will be stuck on the EVMPool, with esssentially no way out as the proof already got verified and the note is already been used to withdraw.

  
## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
