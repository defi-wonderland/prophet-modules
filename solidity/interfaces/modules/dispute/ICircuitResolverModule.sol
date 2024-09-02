// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';
import {IDisputeModule} from '@defi-wonderland/prophet-core/solidity/interfaces/modules/dispute/IDisputeModule.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IAccountingExtension} from '../../extensions/IAccountingExtension.sol';

/**
 * @title CircuitResolverModule
 * @notice Module allowing users to dispute a proposed response by bonding tokens.
 * The module will invoke the circuit verifier supplied to calculate
 * the proposed response and compare it to the correct response.
 * - If the dispute is valid, the disputer wins and their bond is returned along with a reward.
 * - If the dispute is invalid, the bond is forfeited and returned to the proposer.
 *
 * After the dispute is settled, the correct response is automatically proposed to the oracle
 * and the request is finalized.
 */
interface ICircuitResolverModule is IDisputeModule {
  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Thrown when the verification of a response fails
   */
  error CircuitResolverModule_VerificationFailed();

  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Parameters of the request as stored in the module
   *
   * @param callData The encoded data forwarded to the verifier
   * @param verifier The address of the verifier contract
   * @param accountingExtension The address of the accounting extension
   * @param bondToken The address of the bond token
   * @param bondSize The size of the bond
   */
  struct RequestParameters {
    bytes callData;
    address verifier;
    IAccountingExtension accountingExtension;
    IERC20 bondToken;
    uint256 bondSize;
  }

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Returns the decoded data for a request
   *
   * @param   _data The encoded request parameters
   * @return  _params The decoded parameters of the request
   */
  function decodeRequestData(bytes calldata _data) external view returns (RequestParameters memory _params);

  /**
   * @notice Initiates and resolves the dispute by comparing the proposed response with the one returned by the verifier
   *
   * @dev This function will notify the oracle about the outcome of the dispute
   * @param _request  The request that the response was proposed to
   * @param _response The response that is being disputed
   * @param _dispute  The dispute created by the oracle
   */
  function disputeResponse(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external;

  /**
   * @notice Depending on the status of the dispute, either pays the disputer and submits the correct response,
   * or pays the proposer. Finalizes the request in any case.
   *
   * @param _disputeId  The id of the dispute
   * @param _request    The request
   * @param _response   The response that was disputed
   * @param _dispute    The dispute
   */
  function onDisputeStatusChange(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external;
}
