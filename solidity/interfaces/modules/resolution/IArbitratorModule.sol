// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IResolutionModule} from
  '@defi-wonderland/prophet-core-contracts/solidity/interfaces/modules/resolution/IResolutionModule.sol';

/*
  * @title ArbitratorModule
  * @notice Module allowing an external arbitrator contract
  * to resolve a dispute.
  */
interface IArbitratorModule is IResolutionModule {
  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Thrown when an unauthorized caller calls a function only the arbitrator can call
   */
  error ArbitratorModule_OnlyArbitrator();

  /**
   * @notice Thrown when trying to resolve a dispute that is not escalated
   */
  error ArbitratorModule_InvalidDisputeId();

  /**
   * @notice Thrown when the arbitrator address is the address zero
   */
  error ArbitratorModule_InvalidArbitrator();

  /**
   * @notice Thrown when the arbitrator returns an invalid resolution status
   */
  error ArbitratorModule_InvalidResolutionStatus();

  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Parameters of the request as stored in the module
   * @param arbitrator The address of the arbitrator
   */
  struct RequestParameters {
    address arbitrator;
  }

  /*///////////////////////////////////////////////////////////////
                              ENUMS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Available status of the arbitration process
   */
  enum ArbitrationStatus {
    Unknown, // The arbitration process has not started (default)
    Active, // The arbitration process is active
    Resolved // The arbitration process is resolved
  }

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Returns the current arbitration status of a dispute
   * @param _disputeId The ID of the dispute
   * @return _disputeStatus The `ArbitrationStatus` of the dispute
   */
  function getStatus(bytes32 _disputeId) external view returns (ArbitrationStatus _disputeStatus);

  /**
   * @notice Starts the arbitration process by calling `resolve` on the
   * arbitrator and flags the dispute as Active
   * @dev Only callable by the Oracle
   * @dev Will revert if the arbitrator address is the address zero
   * @param _disputeId The ID of the dispute
   */
  function startResolution(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external;

  /**
   * @notice Resolves the dispute by getting the answer from the arbitrator
   * and updating the dispute status
   * @dev Only callable by the Oracle
   * @param _disputeId The ID of the dispute
   */
  function resolveDispute(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external;

  /**
   * @notice Returns the decoded data for a request
   * @param _data The encoded request parameters
   * @return _params The struct containing the parameters for the request
   */
  function decodeRequestData(bytes calldata _data) external view returns (RequestParameters memory _params);
}
