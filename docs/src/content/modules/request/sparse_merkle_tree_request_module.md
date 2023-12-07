# Sparse Merkle Tree Request Module

See [ISparseMerkleTreeRequestModule.sol](/solidity/interfaces/modules/request/ISparseMerkleTreeRequestModule.sol/interface.ISparseMerkleTreeRequestModule.md) for more details.

## 1. Introduction

The `SparseMerkleTreeRequestModule` is a contract that allows a user to request the calculation of a Merkle tree after inserting a set of leaves.

## 2. Contract Details

### Key Methods

- `decodeRequestData`: Decodes request parameters. It returns a RequestParameters struct that contains the parameters for the request.
- `createRequest`: Can be used to bond the requester's funds and validating the request parameters.
- `finalizeRequest`: Finalizes a request by paying the proposer if there is a valid response, or releases the requester bond if no valid response was provided.

### Request Parameters

- `treeData`: The encoded Merkle tree data parameters for the tree verifier.
- `leavesToInsert`: The array of leaves to insert into the Merkle tree.
- `treeVerifier`: The tree verifier to calculate the root.
- `accountingExtension`: The accounting extension to use for the request.
- `paymentToken`: The payment token to use for the request.
- `paymentAmount`: The payment amount to use for the request.

## 3. Key Mechanisms & Concepts

- The `SparseMerkleTreeRequestModule` uses a Merkle tree to calculate the root from a set of leaves. The verifier contract is used to calculate the Merkle root hash given a set of Merkle tree branches and Merkle tree leaves count.
- Check out [Accounting Extension](../../extensions/accounting.md).

## 4. Gotchas

- The module is supposed to be paired with [`RootVerificationModule`](../dispute/root_verification_module.md).
- The verifier contract must follow the `ITreeVerifier` interface, otherwise the proposers won't be able to calculate the correct response.
