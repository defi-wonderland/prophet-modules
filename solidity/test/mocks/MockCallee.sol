// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract MockCallee {
  fallback(bytes calldata _data) external payable returns (bytes memory _ret) {
    _ret = _data;
  }
}
