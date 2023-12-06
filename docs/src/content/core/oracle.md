# Oracle

See [IOracle.sol](/solidity/interfaces/core/IOracle.sol/interface.IOracle.md) for more details.

## 1. Introduction

The Oracle serves as the central part of the Prophet framework. It performs the following functions:

- Managing requests, responses and disputes.
- Routing function calls to appropriate modules.
- Keeping data synchronized between different modules.
- Providing the users with the full picture of their request, response or dispute.

The Oracle does not handle any transfers, utilizing the extensions for that functionality.

## 2. Contract Details

### Key Methods

- `createRequest`: Creates a new request.
- `createRequests`: Creates multiple requests at once.
- `proposeResponse`: Proposes a response to a request.
- `disputeResponse`: Disputes a response to a request.
- `escalateDispute`: Escalates a dispute to the next level.
- `resolveDispute`: Stores the resolution outcome and changes the dispute status.
- `updateDisputeStatus`: Updates the status of a dispute.
- `finalize`: Finalizes a request.

## 3. Key Mechanisms & Concepts

### Stored data

The oracle keeps almost no data in storage, instead relying on events to help off-chain agents track the state of requests, responses and disputes.

### Request, response, dispute IDs
The IDs are calculated as keccak256 hash of the request, response or dispute data. This allows for easy verification of the data integrity and uniqueness.


### Finalization
The oracle supports 2 ways of finalizing a request.

1. In case there is a non-disputed response, the request can be finalized by calling `finalize` function and providing the final response. The oracle will call `finalizeRequest` on the modules and mark the request as finalized. Usually the `finalizeRequest` hook will issue the reward to the proposer.

2. If no responses have been submitted, or they're all disputed, the request can be finalized by calling `finalize` function with a response that has its request ID set to 0. The same hook will be executed in all modules, refunding the requester and marking the request as finalized.

## 4. Gotchas

### Request misconfiguration

Due to the modular and open nature of the framework, the oracle does not have any rules or validations, and a request is deemed correct unless it reverts on creation (`createRequest` hook). It’s the requester’s responsibility to choose sensible parameters and avoid the request being unattractive to proposers and disputers, impossible to answer or finalize.

The same can be said about engaging with a request. Off-chain validation must be done prior to proposing or disputing any response to avoid the loss of funds. We strongly encourage keeping a list of trusted modules and extensions and avoid interactions with unverified ones.
