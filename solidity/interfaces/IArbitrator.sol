// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';

interface IArbitrator {
  /**
   * @notice Returns the status of a dispute
   * @param _dispute The ID of the dispute
   * @return _status The status of the dispute
   */
  function getAnswer(
    bytes32 _dispute
  ) external returns (IOracle.DisputeStatus _status);

  /**
   * @notice Resolves a dispute
   * @param _request The request object
   * @param _response The response object
   * @param _dispute The dispute object
   * @return _data The data for the dispute resolution
   */
  function resolve(
    IOracle.Request memory _request,
    IOracle.Response memory _response,
    IOracle.Dispute memory _dispute
  ) external returns (bytes memory _data);
}
