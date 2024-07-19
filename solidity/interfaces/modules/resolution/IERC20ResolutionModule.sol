// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IResolutionModule} from
  '@defi-wonderland/prophet-core-contracts/solidity/interfaces/modules/resolution/IResolutionModule.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IAccountingExtension} from '../../extensions/IAccountingExtension.sol';

/**
 * @title ERC20ResolutionModule
 * @notice This contract allows for disputes to be resolved by a voting process.
 * The voting process is started by the oracle and
 * the voting phase lasts for a certain amount of time. During this time, anyone can vote on the dispute. Once the voting
 * phase is over, the votes are tallied and if the votes in favor of the dispute are greater than the votes against the
 * dispute, the dispute is resolved in favor of the dispute. Otherwise, the dispute is resolved against the dispute.
 */
interface IERC20ResolutionModule is IResolutionModule {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Emitted when a voter casts their vote on a dispute
   * @param _voter The address of the voter
   * @param _disputeId The id of the dispute
   * @param _numberOfVotes The number of votes cast by the voter
   */
  event VoteCast(address _voter, bytes32 _disputeId, uint256 _numberOfVotes);

  /**
   * @notice Emitted when the voting phase has started
   * @param _startTime The time when the voting phase started
   * @param _disputeId The ID of the dispute
   */
  event VotingPhaseStarted(uint256 _startTime, bytes32 _disputeId);

  /**
   * @notice Emitted when the voter gets back their bond
   * @param _voter The voter who has claimed their bond
   * @param _disputeId The id of the dispute
   * @param _amount The amount of tokens claimed
   */
  event VoteClaimed(address _voter, bytes32 _disputeId, uint256 _amount);

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Throws if the caller is not the dispute module
   */
  error ERC20ResolutionModule_OnlyDisputeModule();

  /**
   * @notice Thrown when a request does not match a request id
   */
  error ERC20ResolutionModule_InvalidRequestId();

  /**
   * @notice Throws if the dispute doesn't exist or has not been escalated
   */
  error ERC20ResolutionModule_DisputeNotEscalated();

  /**
   * @notice Throws if the dispute is unresolved
   */
  error ERC20ResolutionModule_UnresolvedDispute();

  /**
   * @notice Throws if the voting phase is over
   */
  error ERC20ResolutionModule_VotingPhaseOver();

  /**
   * @notice Throws if the voting phase is ongoing
   */
  error ERC20ResolutionModule_OnGoingVotingPhase();

  /**
   * @notice Throws if the dispute has already been resolved
   */
  error ERC20ResolutionModule_AlreadyResolved();

  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Parameters of the request as stored in the module
   * @param accountingExtension The accounting extension to bond and release funds
   * @param votingToken The token used to vote
   * @param minVotesForQuorum The minimum amount of votes to win the dispute
   * @param timeUntilDeadline The time until the voting phase ends
   */
  struct RequestParameters {
    IAccountingExtension accountingExtension;
    IERC20 votingToken;
    uint256 minVotesForQuorum;
    uint256 timeUntilDeadline;
  }

  /**
   * @notice Escalation data for a dispute
   * @param startTime The timestamp at which the dispute was escalated
   * @param totalVotes The total amount of votes cast for the dispute
   */
  struct Escalation {
    uint256 startTime;
    uint256 totalVotes;
  }

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Returns the escalation data for a dispute
   *
   * @param _disputeId    The id of the dispute
   * @return _startTime   The timestamp at which the dispute was escalated
   * @return _totalVotes  The total amount of votes cast for the dispute
   */
  function escalations(bytes32 _disputeId) external view returns (uint256 _startTime, uint256 _totalVotes);

  /**
   * @notice Returns the amount of votes the given voter has cast for the given dispute
   *
   * @param _disputeId  The id of the dispute
   * @param _voter      The address of the voter
   * @return _votes     The amount of votes the voter has cast
   */
  function votes(bytes32 _disputeId, address _voter) external view returns (uint256 _votes);

  /**
   * @notice Returns the decoded data for a request
   *
   * @param _data     The encoded request parameters
   * @return _params  The struct containing the parameters for the request
   */
  function decodeRequestData(bytes calldata _data) external view returns (RequestParameters memory _params);

  /**
   * @notice Casts a vote in favor of a dispute
   *
   * @param _disputeId  The id of the dispute
   * @param _request    The request for which the dispute was created
   * @param _response   The disputed response
   * @param _dispute    The dispute for which the vote is being cast
   */
  function startResolution(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external;

  /**
   * @notice Casts a vote in favor of a dispute
   *
   * @param _request        The request for which the dispute was created
   * @param _dispute        The dispute for which the vote is being cast
   * @param _numberOfVotes  The number of votes to cast
   */
  function castVote(
    IOracle.Request calldata _request,
    IOracle.Dispute calldata _dispute,
    uint256 _numberOfVotes
  ) external;

  /**
   * @notice Settles the dispute, transferring the funds back to the voters
   *
   * @param _disputeId  The id of the dispute
   * @param _request    The request for which the dispute was created
   * @param _response   The disputed response
   * @param _dispute    The dispute that is being resolved
   */
  function resolveDispute(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external;

  /**
   * @notice Releases the voter's bond
   *
   * @param _request  The request for which the dispute was created
   * @param _dispute  The resolved dispute
   */
  function claimVote(IOracle.Request calldata _request, IOracle.Dispute calldata _dispute) external;

  /**
   * @notice Gets the voters of a dispute
   *
   * @param _disputeId  The id of the dispute
   * @return _voters    The addresses of the voters
   */
  function getVoters(bytes32 _disputeId) external view returns (address[] memory _voters);
}
