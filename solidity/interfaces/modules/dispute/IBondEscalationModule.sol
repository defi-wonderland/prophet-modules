// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IDisputeModule} from
  '@defi-wonderland/prophet-core-contracts/solidity/interfaces/modules/dispute/IDisputeModule.sol';

import {IBondEscalationAccounting} from '../../extensions/IBondEscalationAccounting.sol';

/**
 * @title BondEscalationModule
 * @notice Module allowing users to have the first dispute of a request go through the bond escalation mechanism.
 */
interface IBondEscalationModule is IDisputeModule {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice A pledge has been made in favor of a dispute.
   *
   * @param _disputeId The id of the dispute the pledger is pledging in favor of.
   * @param _pledger   The address of the pledger.
   * @param _amount    The amount pledged.
   */
  event PledgedForDispute(bytes32 indexed _disputeId, address indexed _pledger, uint256 indexed _amount);

  /**
   * @notice A pledge has been made against a dispute.
   *
   * @param _disputeId The id of the dispute the pledger is pledging against.
   * @param _pledger   The address of the pledger.
   * @param _amount    The amount pledged.
   */
  event PledgedAgainstDispute(bytes32 indexed _disputeId, address indexed _pledger, uint256 indexed _amount);

  /**
   * @notice The status of the bond escalation mechanism has been updated.
   *
   * @param _requestId The id of the request associated with the bond escalation mechanism.
   * @param _disputeId The id of the dispute going through the bond escalation mechanism.
   * @param _status    The new status.
   */
  event BondEscalationStatusUpdated(
    bytes32 indexed _requestId, bytes32 indexed _disputeId, BondEscalationStatus _status
  );

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Thrown when trying to escalate a dispute going through the bond escalation module before its deadline.
   */
  error BondEscalationModule_BondEscalationNotOver();
  /**
   * @notice Thrown when trying to pledge for a dispute that is not going through the bond escalation mechanism.
   */
  error BondEscalationModule_InvalidDispute();
  /**
   * @notice Thrown when the number of escalation pledges of a given dispute has reached its maximum.
   */
  error BondEscalationModule_MaxNumberOfEscalationsReached();
  /**
   * @notice Thrown when trying to settle a dispute that went through the bond escalation when it's not active.
   */
  error BondEscalationModule_BondEscalationCantBeSettled();
  /**
   * @notice Thrown when trying to settle a bond escalation process that is not tied.
   */
  error BondEscalationModule_ShouldBeEscalated();
  /**
   * @notice Thrown when trying to break a tie after the tying buffer has started.
   */
  error BondEscalationModule_CannotBreakTieDuringTyingBuffer();
  /**
   * @notice Thrown when the max number of escalations or the bond size is set to 0.
   */
  error BondEscalationModule_ZeroValue();
  /**
   * @notice Thrown when trying to pledge after the bond escalation deadline.
   */
  error BondEscalationModule_BondEscalationOver();
  /**
   * @notice Thrown when trying to escalate a dispute going through the bond escalation process that is not tied
   *         or that is not active.
   */
  error BondEscalationModule_NotEscalatable();
  /**
   * @notice Thrown when trying to pledge for a dispute that does not exist
   */
  error BondEscalationModule_DisputeDoesNotExist();
  /**
   * @notice Thrown when trying to surpass the number of pledges of the other side by more than 1 in the bond escalation mechanism.
   */
  error BondEscalationModule_CanOnlySurpassByOnePledge();
  /**
   * @notice Thrown when trying to dispute a response after the dispute period expired.
   */
  error BondEscalationModule_DisputeWindowOver();
  /**
   * @notice Thrown when trying to set up a request with invalid bond size or maximum amount of escalations.
   */
  error BondEscalationModule_InvalidEscalationParameters();

  /*///////////////////////////////////////////////////////////////
                              ENUMS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Enum holding all the possible statuses of a dispute going through the bond escalation mechanism.
   */
  enum BondEscalationStatus {
    None, // Dispute is not going through the bond escalation mechanism.
    Active, // Dispute is going through the bond escalation mechanism.
    Escalated, // Dispute is going through the bond escalation mechanism and has been escalated.
    DisputerLost, // An escalated dispute has been settled and the disputer lost.
    DisputerWon // An escalated dispute has been settled and the disputer won.
  }

  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Parameters of the request as stored in the module
   *
   * @param _accountingExtension        Address of the accounting extension associated with the given request
   * @param _bondToken                  Address of the token associated with the given request
   * @param _bondSize                   Amount to bond to dispute or propose an answer for the given request
   * @param _numberOfEscalations        Maximum allowed escalations or pledges for each side during the bond escalation process
   * @param _bondEscalationDeadline     Timestamp at which bond escalation process finishes when pledges are not tied
   * @param _tyingBuffer                Number of seconds to extend the bond escalation process to allow the losing
   *                                    party to tie if at the end of the initial deadline the pledges weren't tied.
   * @param _disputeWindow              Number of seconds disputers have to challenge the proposed response since its creation.
   */
  struct RequestParameters {
    IBondEscalationAccounting accountingExtension;
    IERC20 bondToken;
    uint256 bondSize;
    uint256 maxNumberOfEscalations;
    uint256 bondEscalationDeadline;
    uint256 tyingBuffer;
    uint256 disputeWindow;
  }

  /**
   * @notice Data of a dispute going through the bond escalation.
   *
   * @param disputeId                       The id of the dispute being bond-escalated.
   * @param status                          The status of the bond escalation.
   * @param amountOfPledgesForDispute       The amount of pledges made in favor of the dispute.
   * @param amountOfPledgesAgainstDispute   The amount of pledges made against the dispute.
   */
  struct BondEscalation {
    bytes32 disputeId;
    BondEscalationStatus status;
    uint256 amountOfPledgesForDispute;
    uint256 amountOfPledgesAgainstDispute;
  }

  /*///////////////////////////////////////////////////////////////
                              VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Returns the escalation data for a request.
   * @param _requestId The id of the request to get its escalation data.
   * @return _escalation The struct containing the escalation data.
   */
  function getEscalation(bytes32 _requestId) external view returns (BondEscalation memory _escalation);

  /**
   * @notice  Returns the decoded data for a request
   * @param   _data The encoded request parameters
   * @return  _params The struct containing the parameters for the request
   */
  function decodeRequestData(bytes calldata _data) external view returns (RequestParameters memory _params);

  /**
   * @notice Returns the amount of pledges that a particular pledger has made for a given dispute.
   * @param _requestId The id of the request to get the pledges for.
   * @param _pledger The address of the pledger to get the pledges for.
   * @return _numPledges The number of pledges made by the pledger for the dispute.
   */
  function pledgesForDispute(bytes32 _requestId, address _pledger) external view returns (uint256 _numPledges);

  /**
   * @notice Returns the amount of pledges that a particular pledger has made against a given dispute.
   * @param _requestId The id of the request to get the pledges for.
   * @param _pledger The address of the pledger to get the pledges for.
   * @return _numPledges The number of pledges made by the pledger against the dispute.
   */
  function pledgesAgainstDispute(bytes32 _requestId, address _pledger) external view returns (uint256 _numPledges);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Disputes a response
   *
   * @dev If this is the first dispute of the request and the bond escalation window is not over,
   *      it will start the bond escalation process. This function must be called through the Oracle.
   *
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
   * @notice Updates the status of a given disputeId and pays the proposer and disputer accordingly. If this
   *         dispute has gone through the bond escalation mechanism, then it will pay the winning pledgers as well.
   *
   * @param _disputeId  The id of the dispute
   * @param _request    The request that the response was proposed to
   * @param _response   The response that was disputed
   * @param _dispute    The dispute being updated
   */
  function onDisputeStatusChange(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external;

  /**
   * @notice Bonds funds in favor of a given dispute during the bond escalation process.
   *
   * @dev This function must be called directly through this contract.
   * @dev If the bond escalation is not tied at the end of its deadline, a tying buffer is added
   *      to avoid scenarios where one of the parties breaks the tie very last second.
   *      During the tying buffer, the losing party can only tie, and once the escalation is tied
   *      no further funds can be pledged.
   *
   * @param _request  The request being disputed on.
   * @param _dispute  The dispute to pledge for.
   */
  function pledgeForDispute(IOracle.Request calldata _request, IOracle.Dispute calldata _dispute) external;

  /**
   * @notice Pledges funds against a given disputeId during its bond escalation process.
   *
   * @dev Must be called directly through this contract. Will revert if the disputeId is not going through
   *         the bond escalation process.
   * @dev If the bond escalation is not tied at the end of its deadline, a tying buffer is added
   *      to avoid scenarios where one of the parties breaks the tie very last second.
   *      During the tying buffer, the losing party can only tie, and once the escalation is tied
   *      no further funds can be pledged.
   *
   * @param _request The request being disputed on.
   * @param _dispute  The dispute to pledge against.
   */
  function pledgeAgainstDispute(IOracle.Request calldata _request, IOracle.Dispute calldata _dispute) external;

  /**
   * @notice Settles the bond escalation process of a given requestId.
   *
   * @dev Must be called directly through this contract.
   * @dev Can only be called if after the deadline + tyingBuffer window is over, the pledges weren't tied
   *
   * @param _request The request to settle the bond escalation process for.
   * @param _response The response to settle the bond escalation process for.
   * @param _dispute The dispute to settle the bond escalation process for.
   */
  function settleBondEscalation(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external;
}
