## Steps involved

- Start local anvil node with Odyssey features enabled

```bash
anvil --odyssey
```

- Anvil comes with pre-funded developer accounts which we can use for the example going forward

```bash
# using anvil dev accounts
export ALICE_ADDRESS="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
export ALICE_PK="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
export BOB_ADDRESS="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
export BOB_PK="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
```

- We need to deploy the EIP7702Proxy contract and its CoinbaseSmartWallet implementation

```bash
forge script script/DeployTemplate.s.sol --broadcast --rpc-url http://localhost:8545
```

- Record the proxy contract address

```bash
export PROXY_TEMPLATE_ADDRESS="0x261D8c5e9742e6f7f1076Fa1F560894524e19cad"
```

<!-- - Generate the initialization data for the proxy contract:

```bash
forge script script/GenerateInitData.s.sol --rpc-url http://localhost:8545
``` -->

```bash
export INIT_CALLDATA="0x1af19f770000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000003c44cdddb6a900fa2b585dd299e03d12fa4293bc00000000000000000000000000000000000000000000000000000000000000416e0c676d16c35c87068e29cec7bc313b3b13e098edab0ce2142f3fa189e093256bb0a86614b98b1ecc153add0cc8e065bc91a3cdaf0aa885a7f32f88451f40241b00000000000000000000000000000000000000000000000000000000000000"
```

- Alice can sign an EIP-7702 authorization using `cast wallet sign-auth` as follows:

```bash
SIGNED_AUTH=$(cast wallet sign-auth $PROXY_TEMPLATE_ADDRESS --private-key $ALICE_PK)
```

- Bob relays the transaction on Alice's behalf using his own private key and thereby paying gas fee from his account:

```bash
cast send $ALICE_ADDRESS $INIT_CALLDATA --private-key $BOB_PK --auth $SIGNED_AUTH
```

- Verify that our auth was successful, by checking Alice's code which now contains the [delegation designation](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-7702.md#delegation-designation) prefix `0xef01`:

```bash
$ cast code $ALICE_ADDRESS
0xef0100...
```

- Verify that our call to initialized happened by checking the contract's state

```bash
cast call $ALICE_ADDRESS "isOwnerAddress(address)" $BOB_ADDRESS --rpc-url http://localhost:8545
```

- Try again to call the contract, this time without the auth flag

```bash
cast send $ALICE_ADDRESS $INIT_CALLDATA --private-key $BOB_PK
```

- Verify the state once more, the state has changed!

```bash
cast call $ALICE_ADDRESS "isOwnerAddress(address)" $BOB_ADDRESS --rpc-url http://localhost:8545
```
