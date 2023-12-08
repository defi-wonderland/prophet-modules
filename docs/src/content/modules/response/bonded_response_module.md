# Bonded Response Module

See [IBondedResponseModule.sol](/solidity/interfaces/modules/response/IBondedResponseModule.sol/interface.IBondedResponseModule.md) for more details.

## 1. Introduction

The Bonded Response Module is a contract that allows users to propose a response for a request by bonding tokens.

## 2. Contract Details

### Key Methods

- `decodeRequestData`: Decodes request parameters.
- `propose`: Proposes a response for a request, bonding the proposer's tokens. A response cannot be proposed after the deadline or if an undisputed response has already been proposed.
- `finalizeRequest`: Finalizes the request, paying the proposer of the final response.

### Request Parameters

- `accountingExtension`: The address holding the bonded tokens. It must implement the [IAccountingExtension.sol](/solidity/interfaces/extensions/IAccountingExtension.sol/interface.IAccountingExtension.md) interface.
- `bondToken`: The ERC20 token used for bonding.
- `bondSize`: The amount of tokens the disputer must bond to be able to dispute a response.
- `deadline`: The timestamp at which the module stops accepting new responses for a request and it becomes finalizable.

## 3. Key Mechanisms & Concepts

- **Early finalization**: It is possible for pre-dispute modules to atomically calculate the correct response on-chain, decide on the result of a dispute and finalize the request before its deadline.
- **Dispute window**: Prevents proposers from submitting a response 1 block before the deadline and finalizing it in the next block, leaving disputers no time to dispute the response.
