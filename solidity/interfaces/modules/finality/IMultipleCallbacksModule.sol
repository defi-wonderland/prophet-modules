// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';
import {IFinalityModule} from '@defi-wonderland/prophet-core/solidity/interfaces/modules/finality/IFinalityModule.sol';

/**
 * @title MultipleCallbackModule
 * @notice Module allowing users to make multiple calls to different contracts
 * as a result of a request being finalized.
 */
interface IMultipleCallbacksModule is IFinalityModule {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice A callback has been executed
   * @param _requestId The id of the request being finalized
   * @param _target The target address for the callback
   * @param _data The calldata forwarded to the _target
   */
  event Callback(bytes32 indexed _requestId, address indexed _target, bytes _data);

  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Parameters of the request as stored in the module
   * @param targets The target addresses for the callback
   * @param data The calldata forwarded to the targets
   */
  struct RequestParameters {
    address[] targets;
    bytes[] data;
  }

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Returns the decoded data for a request
   *
   * @param _data     The encoded request parameters
   * @return _params  The struct containing the parameters for the request
   */
  function decodeRequestData(
    bytes calldata _data
  ) external view returns (RequestParameters memory _params);

  /**
   * @notice Finalizes the request by executing the callback calls on the targets
   *
   * @dev               The success of the callback calls is purposely not checked
   * @param _request    The request being finalized
   * @param _response   The response
   * @param _finalizer  The address finalizing the request
   */
  function finalizeRequest(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    address _finalizer
  ) external;
}
