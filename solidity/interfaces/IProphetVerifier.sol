// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IProphetVerifier {
  /**
   * @notice Verification function for the Prophet modules
   * @param _callData The encoded data for the verification
   * @return _callResponse The encoded response for the verification
   */
  function prophetVerify(
    bytes calldata _callData
  ) external returns (bytes memory _callResponse);
}
