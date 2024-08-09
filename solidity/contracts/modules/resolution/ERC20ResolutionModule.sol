// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// solhint-disable-next-line no-unused-import
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import {IModule, Module} from '@defi-wonderland/prophet-core/solidity/contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';

import {IERC20ResolutionModule} from '../../../interfaces/modules/resolution/IERC20ResolutionModule.sol';

contract ERC20ResolutionModule is Module, IERC20ResolutionModule {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  /// @inheritdoc IERC20ResolutionModule
  mapping(bytes32 _disputeId => Escalation _escalation) public escalations;

  /// @inheritdoc IERC20ResolutionModule
  mapping(bytes32 _disputeId => mapping(address _voter => uint256 _numOfVotes)) public votes;

  /**
   * @notice The list of voters for each dispute
   */
  mapping(bytes32 _disputeId => EnumerableSet.AddressSet _votersSet) internal _voters;

  constructor(IOracle _oracle) Module(_oracle) {}

  /// @inheritdoc IModule
  function moduleName() external pure returns (string memory _moduleName) {
    return 'ERC20ResolutionModule';
  }

  /// @inheritdoc IERC20ResolutionModule
  function decodeRequestData(bytes calldata _data) public pure returns (RequestParameters memory _params) {
    _params = abi.decode(_data, (RequestParameters));
  }

  /// @inheritdoc IERC20ResolutionModule
  function startResolution(
    bytes32 _disputeId,
    IOracle.Request calldata, /* _request */
    IOracle.Response calldata, /* _response */
    IOracle.Dispute calldata /* _dispute */
  ) external onlyOracle {
    escalations[_disputeId].startTime = block.timestamp;
    emit VotingPhaseStarted(block.timestamp, _disputeId);
  }

  /// @inheritdoc IERC20ResolutionModule
  function castVote(
    IOracle.Request calldata _request,
    IOracle.Dispute calldata _dispute,
    uint256 _numberOfVotes
  ) public {
    bytes32 _disputeId = _validateDispute(_request, _dispute);
    Escalation memory _escalation = escalations[_disputeId];
    if (_escalation.startTime == 0) revert ERC20ResolutionModule_DisputeNotEscalated();
    if (ORACLE.disputeStatus(_disputeId) != IOracle.DisputeStatus.Escalated) {
      revert ERC20ResolutionModule_AlreadyResolved();
    }

    RequestParameters memory _params = decodeRequestData(_request.resolutionModuleData);
    uint256 _deadline = _escalation.startTime + _params.timeUntilDeadline;
    if (block.timestamp >= _deadline) revert ERC20ResolutionModule_VotingPhaseOver();

    votes[_disputeId][msg.sender] += _numberOfVotes;

    _voters[_disputeId].add(msg.sender);
    escalations[_disputeId].totalVotes += _numberOfVotes;

    _params.accountingExtension.bond(msg.sender, _dispute.requestId, _params.votingToken, _numberOfVotes);
    emit VoteCast(msg.sender, _disputeId, _numberOfVotes);
  }

  /// @inheritdoc IERC20ResolutionModule
  function resolveDispute(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external onlyOracle {
    // Check disputeId actually exists and that it isn't resolved already
    if (ORACLE.disputeStatus(_disputeId) != IOracle.DisputeStatus.Escalated) {
      revert ERC20ResolutionModule_AlreadyResolved();
    }

    // Check that the dispute is actually escalated
    Escalation memory _escalation = escalations[_disputeId];
    if (_escalation.startTime == 0) revert ERC20ResolutionModule_DisputeNotEscalated();

    // Check that voting deadline is over
    RequestParameters memory _params = decodeRequestData(_request.resolutionModuleData);
    uint256 _deadline = _escalation.startTime + _params.timeUntilDeadline;
    if (block.timestamp < _deadline) revert ERC20ResolutionModule_OnGoingVotingPhase();

    uint256 _quorumReached = _escalation.totalVotes >= _params.minVotesForQuorum ? 1 : 0;

    // Update status
    if (_quorumReached == 1) {
      ORACLE.updateDisputeStatus(_request, _response, _dispute, IOracle.DisputeStatus.Won);
      emit DisputeResolved(_dispute.requestId, _disputeId, IOracle.DisputeStatus.Won);
    } else {
      ORACLE.updateDisputeStatus(_request, _response, _dispute, IOracle.DisputeStatus.Lost);
      emit DisputeResolved(_dispute.requestId, _disputeId, IOracle.DisputeStatus.Lost);
    }
  }

  /// @inheritdoc IERC20ResolutionModule
  function claimVote(IOracle.Request calldata _request, IOracle.Dispute calldata _dispute) external {
    bytes32 _disputeId = _validateDispute(_request, _dispute);
    Escalation memory _escalation = escalations[_disputeId];

    // Check that voting deadline is over
    RequestParameters memory _params = decodeRequestData(_request.resolutionModuleData);
    uint256 _deadline = _escalation.startTime + _params.timeUntilDeadline;
    if (block.timestamp < _deadline) revert ERC20ResolutionModule_OnGoingVotingPhase();

    // Transfer the tokens back to the voter
    uint256 _amount = votes[_disputeId][msg.sender];
    _params.accountingExtension.release(msg.sender, _dispute.requestId, _params.votingToken, _amount);

    emit VoteClaimed(msg.sender, _disputeId, _amount);
  }

  /// @inheritdoc IERC20ResolutionModule
  function getVoters(bytes32 _disputeId) external view returns (address[] memory __voters) {
    __voters = _voters[_disputeId].values();
  }

  /// @inheritdoc IModule
  function validateParameters(bytes calldata _encodedParameters)
    external
    pure
    override(Module, IModule)
    returns (bool _valid)
  {
    RequestParameters memory _params = decodeRequestData(_encodedParameters);
    _valid = address(_params.accountingExtension) != address(0) && address(_params.votingToken) != address(0)
      && _params.minVotesForQuorum != 0 && _params.timeUntilDeadline != 0;
  }
}
