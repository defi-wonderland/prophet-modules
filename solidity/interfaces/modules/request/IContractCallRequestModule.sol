// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IRequestModule} from
  '@defi-wonderland/prophet-core-contracts/solidity/interfaces/modules/request/IRequestModule.sol';

import {IAccountingExtension} from '../../../interfaces/extensions/IAccountingExtension.sol';

/**
 * @title ContractCallRequestModule
 * @notice Request module for making contract calls
 */
interface IContractCallRequestModule is IRequestModule {
  /**
   * @notice Parameters of the request as stored in the module
   * @param target The address of the contract to do the call on
   * @param functionSelector The selector of the function to call
   * @param data The encoded arguments of the function to call (optional)
   * @param accountingExtension The accounting extension to bond and release funds
   * @param paymentToken The token in which the response proposer will be paid
   * @param paymentAmount The amount of `paymentToken` to pay to the response proposer
   */
  struct RequestParameters {
    address target;
    bytes4 functionSelector;
    bytes data;
    IAccountingExtension accountingExtension;
    IERC20 paymentToken;
    uint256 paymentAmount;
  }

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
