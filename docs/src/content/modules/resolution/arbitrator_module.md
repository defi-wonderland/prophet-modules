# Arbitrator Module

See [IArbitratorModule.sol](/solidity/interfaces/modules/resolution/IArbitratorModule.sol/interface.IArbitratorModule.md) for more details.

## 1. Introduction

The Arbitrator Module is a part of the dispute resolution system. It allows an external arbitrator contract to resolve a dispute. The module provides methods to start the arbitration process, resolve the dispute, and get the status and validity of a dispute.

## 2. Contract Details

### Key Methods

- `getStatus`: Returns the arbitration status of a dispute.
- `isValid`: Indicates whether the dispute has been arbitrated.
- `startResolution`: Starts the arbitration process by calling `resolve` on the arbitrator and flags the dispute as `Active`.
- `resolveDispute`: Resolves the dispute by getting the answer from the arbitrator and notifying the oracle.
- `decodeRequestData`: Returns the decoded data for a request.

### Request Parameters

- `arbitrator`: The address of the arbitrator. The contract must follow the `IArbitrator` interface.

## 3. Key Mechanisms & Concepts

The Arbitrator Module uses an external arbitrator contract to resolve disputes. The arbitration process can be in one of three states:
- Unknown (default)
- Active
- Resolved

The process starts with the `startResolution` function, which sets the dispute status to `Active`. The `resolveDispute` function is then used to get the answer from the arbitrator and update the dispute status to `Resolved`.

## 4. Gotchas

- The status of the arbitration is stored in the `_disputeData` mapping along with the dispute status. They're both packed in a `uint256`.
- The `startResolution` function will revert if the arbitrator address is the address zero.
- If the chosen arbitrator does not implement `resolve` nor `getAnswer` function, the dispute will get stuck in the `Active` state.
