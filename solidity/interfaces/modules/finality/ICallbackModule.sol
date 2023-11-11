// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IFinalityModule} from
  '@defi-wonderland/prophet-core-contracts/solidity/interfaces/modules/finality/IFinalityModule.sol';

/**
 * @title CallbackModule
 * @notice Module allowing users to call a function on a contract
 * as a result of a request being finalized.
 */
interface ICallbackModule is IFinalityModule {
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
   * @param target The target address for the callback
   * @param data The calldata forwarded to the _target
   */
  struct RequestParameters {
    address target;
    bytes data;
  }

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Returns the decoded data for a request
   * @param _data The encoded request parameters
   * @return _params The struct containing the parameters for the request
   */
  function decodeRequestData(bytes calldata _data) external view returns (RequestParameters memory _params);

  /**
   * @notice Finalizes the request by executing the callback call on the target
   * @dev The success of the callback call is purposely not checked
   * @param _request The request being finalized
   * @param _response The final response
   * @param _finalizer The address that initiated the finalization
   */
  function finalizeRequest(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    address _finalizer
  ) external;
}
