# Sparse Merkle Tree Verifier

See [ITreeVerifier.sol](/solidity/interfaces/ITreeVerifier.sol/interface.ITreeVerifier.md) for more details.

## 1. Introduction

The `SparseMerkleTreeL32Verifier` contract is an example of a verifier contract that implements the `ITreeVerifier` interface. It is supposed to be used in tandem with the [`RootVerificationModule`](../modules/dispute/root_verification_module.md).

## 2. Contract Details

### Key Methods

The main method in this contract is `calculateRoot` that calculates a new root from the given one and the leaves to be inserted. The contract expects the tree to have at most 32 levels of depth.

## 3. Key Mechanisms & Concepts

The contract uses the [`MerkleLib`](https://github.com/connext/monorepo/blob/main/packages/deployments/contracts/contracts/messaging/libraries/MerkleLib.sol) library for handling operations related to the Merkle tree.
