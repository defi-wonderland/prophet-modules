// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IProphetCallback} from '../../interfaces/IProphetCallback.sol';

contract MockCallback is IProphetCallback {
  function prophetCallback(
    bytes calldata /* _callData */
  ) external pure returns (bytes memory _callResponse) {
    _callResponse = abi.encode(true);
  }
}
