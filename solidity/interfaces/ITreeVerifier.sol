// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ITreeVerifier {
  /**
   * @notice Calculates the Merkle root hash given a set of Merkle tree branches and merkle tree leaves count.
   * @param _treeData The encoded Merkle tree data parameters for the tree verifier.
   * @param _leavesToInsert The array of leaves to insert into the Merkle tree.
   * @return _calculatedRoot The calculated Merkle root hash.
   */
  function calculateRoot(
    bytes memory _treeData,
    bytes32[] memory _leavesToInsert
  ) external returns (bytes32 _calculatedRoot);
}
