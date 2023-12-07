# Sequential Resolution Module

See [ISequentialResolutionModule.sol](/solidity/interfaces/modules/resolution/ISequentialResolutionModule.sol/interface.ISequentialResolutionModule.md) for more details.

## 1. Introduction

The Sequential Resolution Module is a contract that leverages multiple resolution modules to obtain an answer. If the current resolution module returns no answer, the next resolution is started. The sequence of modules can be configured separately from a request and re-used in multiple requests.

## 2. Contract Details

### Key Methods

- `decodeRequestData`: Decodes request parameters.
- `currentSequenceId`: Returns the last sequence id that was created.
- `currentModuleIndex`: Returns the current index of the submodule in use for a dispute.
- `requestIdForDispute`: Returns the requestId corresponding to a dispute.
- `listSubmodules`: Returns the list of submodules in a sequence.
- `addResolutionModuleSequence`: Creates a sequence of modules.
- `getCurrentResolutionModule`: Returns the module that is currently resolving the specified dispute.
- `resolveDispute`: Resolves a dispute.
- `finalizeRequest`: Finalizes a request with each of the submodules.
- `startResolution`: Initiates the resolution of a dispute, using the first module from the sequence configured for the corresponding request.
- `updateDisputeStatus`: In case a resolution has been achieved, notifies the oracle. Otherwise, starts a resolution using the next submodule.

### Request Parameters

- `sequenceId`: The module sequence to use for resolution.
- `submoduleData`: The array of bytes that will be passed to each submodule.

## 3. Key Mechanisms & Concepts

- Sequence: a list of resolution modules, each of which is asked to resolve a dispute. If it fails, the resolution will continue with the next module in the sequence. It is worth noting that a sequence must be created prior to any requests using it, by calling `addResolutionModuleSequence` and specifying the list of submodules.

## 4. Gotchas

- The module follows the [IOracle.sol](/solidity/interfaces/IOracle.sol/interface.IOracle.md) interface but does not implement the non-view functions from the Oracle.
- Adding an invalid module to a sequence will result in the whole sequence becoming unusable.
- Only resolution modules that support the `NoResolution` status should be used as submodules.
