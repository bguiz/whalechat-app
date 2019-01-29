# WhaleChat smart contracts

## Description

WhaleChat smart contracts are:

- `WcToken.sol`: An ERC20-compliant contract of the WhaleChat token.
- `Cashier.sol`: An ERC721-compliant contract whose tokens, called "tickets", allow the buyer to display a message in the whales-only rooms in the WhaleChat app. These messages can be used to advertise services. The revenue from ticket sales is distributed pro-rata to WhaleChat token holders.
- `TokencraticMultiSigWallet.sol`: Similar to the [Ethereum Multisignature Wallet contract](https://github.com/gnosis/MultiSigWallet), but the code has been changed to allow the WhaleChat token holders to vote on the execution of submitted transactions, which are released only if a majority of token holders decides so. Examples of such transactions are the issuance of new tokens or contract upgrades.

## Bug bounty

A bug bounty is currently ongoing. See [bounty page](bounty.md) for more details.

## Further notes

**The function `updateTokenDistribution()` in `Cashier.sol` needs to be called whenever there is a change in the token distribution in `WcToken.sol`.**


## Development

To run the tests:

```
npm i
scripts/test.sh
```
