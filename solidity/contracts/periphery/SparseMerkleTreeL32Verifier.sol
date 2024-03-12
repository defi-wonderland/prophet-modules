// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ITreeVerifier} from '../../interfaces/ITreeVerifier.sol';

import {MerkleLib} from '../libraries/MerkleLib.sol';

contract SparseMerkleTreeL32Verifier is ITreeVerifier {
  using MerkleLib for MerkleLib.Tree;

  /// @notice The depth of the Merkle tree
  uint256 internal constant _TREE_DEPTH = 32;

  /// @notice A temporary tree created and cleaned up in the calculateRoot function
  MerkleLib.Tree internal _tempTree;

  /// @inheritdoc ITreeVerifier
  function calculateRoot(
    bytes memory _treeData,
    bytes32[] memory _leavesToInsert
  ) external returns (bytes32 _calculatedRoot) {
    bytes32[_TREE_DEPTH] memory _treeBranches;
    uint256 _treeCount;

    (_treeBranches, _treeCount) = abi.decode(_treeData, (bytes32[32], uint256));

    MerkleLib.Tree memory _tree;
    _tree.count = _treeCount;
    _tree.branch = _treeBranches;

    for (uint256 _i; _i < _leavesToInsert.length;) {
      _tree = _tree.insert(_leavesToInsert[_i]);
      unchecked {
        ++_i;
      }
    }

    // The MerkleLib library does not support calling .root() on a memory tree,
    // so we create a temporal storage tree to call .root() on it.
    _tempTree = _tree;
    _calculatedRoot = _tempTree.root();
    delete _tempTree;
  }
}
