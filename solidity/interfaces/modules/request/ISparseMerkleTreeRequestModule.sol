// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';
import {IRequestModule} from '@defi-wonderland/prophet-core/solidity/interfaces/modules/request/IRequestModule.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {ITreeVerifier} from '../../../interfaces/ITreeVerifier.sol';
import {IAccountingExtension} from '../../../interfaces/extensions/IAccountingExtension.sol';

/*
  * @title SparseMerkleTreeRequestModule
  * @notice Module allowing a user to request the calculation
  * of a Merkle tree root from a set of leaves.
  */
interface ISparseMerkleTreeRequestModule is IRequestModule {
  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Parameters of the request as stored in the module
   * @param treeData The encoded Merkle tree data parameters for the tree verifier
   * @param leavesToInsert The array of leaves to insert into the Merkle tree
   * @param treeVerifier The tree verifier to calculate the root
   * @param accountingExtension The accounting extension to use for the request
   * @param paymentToken The payment token to use for the request
   * @param paymentAmount The payment amount to use for the request
   */
  struct RequestParameters {
    bytes treeData;
    bytes32[] leavesToInsert;
    ITreeVerifier treeVerifier;
    IAccountingExtension accountingExtension;
    IERC20 paymentToken;
    uint256 paymentAmount;
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
  function decodeRequestData(bytes calldata _data) external view returns (RequestParameters memory _params);

  /**
   * @notice Executes pre-request logic, bonding the requester's funds
   *
   * @param _requestId  The id of the request
   * @param _data       The encoded request parameters
   * @param _requester  The user who triggered the request
   */
  function createRequest(bytes32 _requestId, bytes calldata _data, address _requester) external;

  /**
   * @notice Finalizes the request by paying the proposer for the response or releasing the requester's bond if no response was submitted
   *
   * @param _request    The request that is being finalized
   * @param _response   The final response
   * @param _finalizer  The user who triggered the finalization
   */
  function finalizeRequest(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    address _finalizer
  ) external;
}
