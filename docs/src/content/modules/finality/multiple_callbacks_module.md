# Multiple Callbacks Module

See [IMultipleCallbacksModule.sol](/solidity/interfaces/modules/finality/IMultipleCallbacksModule.sol/interface.IMultipleCallbacksModule.md) for more details.

## 1. Introduction

The `MultipleCallbacksModule` is a finality module that allows users to make multiple calls to different contracts as a result of a request being finalized. This module is useful when a single request needs to trigger actions in multiple contracts.

## 2. Contract Details

### Key Methods

- `decodeRequestData(bytes calldata _data)`: Returns the decoded data for a request. The returned data includes the target addresses for the callback and the calldata forwarded to the targets.
- `finalizeRequest`: Finalizes the request by executing the callback calls on the targets.

### Request Parameters

- `targets`: The target addresses for the callbacks.
- `data`: The calldata forwarded to the targets.

## 3. Key Mechanisms & Concepts

The `MultipleCallbacksModule` works by storing the target addresses and the calldata for each request. When a request is finalized, the module executes the callback calls on the targets using the stored data.

## 4. Gotchas

- The success of the callback calls in `finalizeRequest` is purposely not checked, specifying a function or parameters that lead to a revert will not stop the request from being finalized.
- All targets must be contracts.
