// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IProphetCallback {
  /**
   * @notice Callback function for the Prophet modules
   * @param _callData The encoded data for the callback
   * @return _callResponse The encoded response for the callback
   */
  function prophetCallback(bytes calldata _callData) external returns (bytes memory _callResponse);
}
