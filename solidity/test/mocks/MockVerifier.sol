// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ITreeVerifier} from '../../interfaces/ITreeVerifier.sol';

contract MockVerifier is ITreeVerifier {
  constructor() {}

  function calculateRoot(
    bytes memory, /* _treeData */
    bytes32[] memory /* _leavesToInsert */
  ) external view returns (bytes32 _calculatedRoot) {
    _calculatedRoot = keccak256(abi.encode(block.timestamp));
  }
}
