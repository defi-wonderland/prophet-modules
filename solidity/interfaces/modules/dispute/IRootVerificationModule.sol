// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IDisputeModule} from
  '@defi-wonderland/prophet-core-contracts/solidity/interfaces/modules/dispute/IDisputeModule.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {ITreeVerifier} from '../../ITreeVerifier.sol';
import {IAccountingExtension} from '../../extensions/IAccountingExtension.sol';

/*
  * @title RootVerificationModule
  * @notice Dispute module allowing disputers to calculate the correct root for a given request and propose it as a response.
  * If the disputer wins the dispute, he is rewarded with the bond of the proposer.
  *
  * @dev This module is a pre-dispute module. It allows disputing and resolving a response in a single call.
  */
interface IRootVerificationModule is IDisputeModule {
  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Thrown when the response length is invalid
   */
  error RootVerificationModule_InvalidResponseLength();

  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Parameters of the request as stored in the module
   * @param treeData The data of the tree
   * @param leavesToInsert The leaves to insert in the tree
   * @param treeVerifier The tree verifier to use to calculate the correct root
   * @param accountingExtension The accounting extension to use for bonds and payments
   * @param bondToken The token to use for bonds and payments
   * @param bondSize The size of the bond to participate in the request
   */
  struct RequestParameters {
    bytes treeData;
    bytes32[] leavesToInsert;
    ITreeVerifier treeVerifier;
    IAccountingExtension accountingExtension;
    IERC20 bondToken;
    uint256 bondSize;
  }
  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Returns the decoded data for a request
   * @param _data The encoded request parameters
   * @return _params The decoded parameters of the request
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
   * @param _request    The request that the response was proposed to
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
