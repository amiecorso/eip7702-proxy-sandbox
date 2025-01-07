## EIP-7702 Proxy

**Proxy contract designed for EIP-7702 accounts.**

> These contracts are unaudited and simple prototypes. Use at your own risk.

### Key features
* Protect initializers with chain-agnostic EOA signatures
* Use existing Smart Account contracts without changes
* Unify contract implementation upgrades using ERC-1967 storage slots

### How to use
1. Deploy an instance of `EIP7702Proxy` pointing to a specific smart account implementation.
1. Sign an EIP-7702 authorization with the EOA
1. Sign an initialization hash with the EOA
1. Submit transaction with EIP-7702 authorization and call to `account.initialize(bytes args, bytes signature)`
    1. `bytes args`: arguments to the smart account implementation's actual initializer function
    1. `bytes signature`: ECDSA signature over the initialization hash from the EOA

Now the EOA has been upgraded to the smart account implementation and had its state initialized.

If the smart account implementation supports UUPS upgradeability, it will work as designed by submitting upgrade calls to the account.

### How does it work?
* `EIP7702Proxy` is constructed with an `initalImplementation` that it will delegate all calls to by default
* `EIP7702Proxy` is constructed with a `guardedInitializer`, the initializer selector of the `initialImplementation`
* Calls to the account on `guardedInitializer` revert and do not delegate the call to the smart account implementation
* `EIP7702Proxy` defines a new, static selector compatible with all initializers: `initialize(bytes args, bytes signature)`
* Calls to the account on `initialize` have their signature validated via ECDSA and the proxy delegates a call combining the `guardedInitializer` and provided `args` to the `initialImplementation`
* The `initialImplementation` is responsible for handling replay protection, which is standard practice among smart accounts
* All other function selectors are undisturbed and this proxy functions akin to a simple ERC-1967 proxy