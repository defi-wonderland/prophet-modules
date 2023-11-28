// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IResponseModule} from
  '@defi-wonderland/prophet-core-contracts/solidity/interfaces/modules/response/IResponseModule.sol';

import {IAccountingExtension} from '../../extensions/IAccountingExtension.sol';

/*
  * @title BondedResponseModule
  * @notice Module allowing users to propose a response for a request by bonding tokens
  */
interface IBondedResponseModule is IResponseModule {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Emitted when a response is proposed
   *
   * @param _requestId The ID of the request that the response was proposed
   * @param _response The proposed response
   * @param _blockNumber The number of the block in which the response was proposed
   */
  event ResponseProposed(bytes32 indexed _requestId, IOracle.Response _response, uint256 indexed _blockNumber);

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Thrown when trying to finalize a request before the deadline
   */
  error BondedResponseModule_TooEarlyToFinalize();

  /**
   * @notice Thrown when trying to propose a response after deadline
   */
  error BondedResponseModule_TooLateToPropose();

  /**
   * @notice Thrown when trying to propose a response while an undisputed response is already proposed
   */
  error BondedResponseModule_AlreadyResponded();

  /**
   * @notice Thrown when trying to release an uncalled response with an invalid request, response or dispute
   */
  error BondedResponseModule_InvalidReleaseParameters();

  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Parameters of the request as stored in the module
   *
   * @param accountingExtension The accounting extension used to bond and release tokens
   * @param bondToken The token used for bonds in the request
   * @param bondSize The amount of `_bondToken` to bond to propose a response and dispute
   * @param deadline The timestamp after which no responses can be proposed
   * @param disputeWindow The time buffer required to finalize a request
   */
  struct RequestParameters {
    IAccountingExtension accountingExtension;
    IERC20 bondToken;
    uint256 bondSize;
    uint256 deadline;
    uint256 disputeWindow;
  }

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Returns the decoded data for a request
   *
   * @param _data The encoded data
   * @return _params The struct containing the parameters for the request
   */
  function decodeRequestData(bytes calldata _data) external pure returns (RequestParameters memory _params);

  /**
   * @notice Proposes a response for a request, bonding the proposer's tokens
   *
   * @dev The user must have previously deposited tokens into the accounting extension
   * @param _request The request to propose a response to
   * @param _response The response being proposed
   * @param _sender The address that initiated the transaction
   */
  function propose(IOracle.Request calldata _request, IOracle.Response calldata _response, address _sender) external;

  /**
   * @notice Finalizes the request by releasing the bond of the proposer
   *
   * @param _request The request that is being finalized
   * @param _response The final response
   * @param _finalizer The user who triggered the finalization
   */
  function finalizeRequest(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    address _finalizer
  ) external;

  /**
   * @notice Releases the proposer fund if the response is valid and it has not been used to finalize the request
   *
   * @param _request The finalized request
   * @param _response The uncalled response
   * @param _response The won dispute
   */
  function releaseUncalledResponse(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external;
}
