// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IDisputeModule} from
  '@defi-wonderland/prophet-core-contracts/solidity/interfaces/modules/dispute/IDisputeModule.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IAccountingExtension} from '../../extensions/IAccountingExtension.sol';

/*
  * @title BondedDisputeModule
  * @notice Module allowing users to dispute a proposed response
  * by bonding tokens. According to the result of the dispute,
  * the tokens are either returned to the disputer or to the proposer.
  */
interface IBondedDisputeModule is IDisputeModule {
  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Thrown when the response proposer tries to dispute the response
   */
  error BondedDisputeModule_OnlyResponseProposer();
  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Parameters of the request as stored in the module
   * @param accountingExtension The address of the accounting extension
   * @param bondToken The address of the bond token
   * @param bondSize The size of the bond
   */
  struct RequestParameters {
    IAccountingExtension accountingExtension;
    IERC20 bondToken;
    uint256 bondSize;
  }

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice  Returns the decoded data for a request
   * @param   _data The encoded request parameters
   * @return  _params The struct containing the parameters for the request
   */
  function decodeRequestData(bytes calldata _data) external view returns (RequestParameters memory _params);

  /**
   * @notice  Called by the oracle when a dispute has been made on a response
   *
   * @dev     Bonds the tokens of the disputer
   * @param   _request The request a dispute has been submitted for
   * @param   _response The response that is being disputed
   * @param   _dispute The dispute that is being submitted
   */
  function disputeResponse(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external;

  /**
   * @notice  Called by the oracle when a dispute status has been updated
   *
   * @dev     According to the result of the dispute, bonds are released to the proposer or paid to the disputer
   * @param   _disputeId The ID of the dispute being updated
   * @param   _request The request a dispute has been submitted for
   * @param   _response The response that is being disputed
   * @param   _dispute The dispute that has changed status
   */
  function onDisputeStatusChange(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external;
}
