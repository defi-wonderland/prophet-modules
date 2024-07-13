// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// solhint-disable-next-line no-unused-import
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

// solhint-disable-next-line no-unused-import
import {IModule, Module} from '@defi-wonderland/prophet-core-contracts/solidity/contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';

import {IPrivateERC20ResolutionModule} from '../../../interfaces/modules/resolution/IPrivateERC20ResolutionModule.sol';

contract PrivateERC20ResolutionModule is Module, IPrivateERC20ResolutionModule {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  /// @inheritdoc IPrivateERC20ResolutionModule
  mapping(bytes32 _disputeId => Escalation _escalation) public escalations;
  /**
   * @notice The data of the voters for a given dispute
   */
  mapping(bytes32 _disputeId => mapping(address _voter => VoterData)) internal _votersData;
  /**
   * @notice The voters addresses for a given dispute
   */
  mapping(bytes32 _disputeId => EnumerableSet.AddressSet _votersSet) internal _voters;

  constructor(IOracle _oracle) Module(_oracle) {}

  /// @inheritdoc IModule
  function moduleName() external pure returns (string memory _moduleName) {
    return 'PrivateERC20ResolutionModule';
  }

  /// @inheritdoc IPrivateERC20ResolutionModule
  function decodeRequestData(bytes calldata _data) public pure returns (RequestParameters memory _params) {
    _params = abi.decode(_data, (RequestParameters));
  }

  /// @inheritdoc IPrivateERC20ResolutionModule
  function startResolution(
    bytes32 _disputeId,
    IOracle.Request calldata, /* _request */
    IOracle.Response calldata, /* _response */
    IOracle.Dispute calldata /* _dispute */
  ) external onlyOracle {
    escalations[_disputeId].startTime = block.timestamp;
    emit CommittingPhaseStarted(block.timestamp, _disputeId);
  }

  /// @inheritdoc IPrivateERC20ResolutionModule
  function commitVote(IOracle.Request calldata _request, IOracle.Dispute calldata _dispute, bytes32 _commitment) public {
    bytes32 _disputeId = _getId(_dispute);
    if (ORACLE.createdAt(_disputeId) == 0) revert PrivateERC20ResolutionModule_NonExistentDispute();
    if (
      ORACLE.disputeStatus(_disputeId) != IOracle.DisputeStatus.None
        && ORACLE.disputeStatus(_disputeId) != IOracle.DisputeStatus.Escalated
    ) {
      revert PrivateERC20ResolutionModule_AlreadyResolved();
    }

    uint256 _startTime = escalations[_disputeId].startTime;
    if (_startTime == 0) revert PrivateERC20ResolutionModule_DisputeNotEscalated();

    RequestParameters memory _params = decodeRequestData(_request.resolutionModuleData);
    uint256 _committingDeadline = _startTime + _params.committingTimeWindow;
    if (block.timestamp >= _committingDeadline) revert PrivateERC20ResolutionModule_CommittingPhaseOver();

    if (_commitment == bytes32('')) revert PrivateERC20ResolutionModule_EmptyCommitment();
    _votersData[_disputeId][msg.sender] = VoterData({numOfVotes: 0, commitment: _commitment});

    emit VoteCommitted(msg.sender, _disputeId, _commitment);
  }

  /// @inheritdoc IPrivateERC20ResolutionModule
  function revealVote(
    IOracle.Request calldata _request,
    IOracle.Dispute calldata _dispute,
    uint256 _numberOfVotes,
    bytes32 _salt
  ) public {
    bytes32 _disputeId = _getId(_dispute);
    Escalation memory _escalation = escalations[_disputeId];
    if (_escalation.startTime == 0) revert PrivateERC20ResolutionModule_DisputeNotEscalated();

    RequestParameters memory _params = decodeRequestData(_request.resolutionModuleData);
    (uint256 _revealStartTime, uint256 _revealEndTime) = (
      _escalation.startTime + _params.committingTimeWindow,
      _escalation.startTime + _params.committingTimeWindow + _params.revealingTimeWindow
    );
    if (block.timestamp <= _revealStartTime) revert PrivateERC20ResolutionModule_OnGoingCommittingPhase();
    if (block.timestamp > _revealEndTime) revert PrivateERC20ResolutionModule_RevealingPhaseOver();

    VoterData storage _voterData = _votersData[_disputeId][msg.sender];

    if (_voterData.commitment != keccak256(abi.encode(msg.sender, _disputeId, _numberOfVotes, _salt))) {
      revert PrivateERC20ResolutionModule_WrongRevealData();
    }

    _voterData.numOfVotes = _numberOfVotes;
    _voterData.commitment = bytes32('');
    _voters[_disputeId].add(msg.sender);
    escalations[_disputeId].totalVotes += _numberOfVotes;

    _params.votingToken.safeTransferFrom(msg.sender, address(this), _numberOfVotes);

    emit VoteRevealed(msg.sender, _disputeId, _numberOfVotes);
  }

  /// @inheritdoc IPrivateERC20ResolutionModule
  function resolveDispute(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external onlyOracle {
    if (ORACLE.createdAt(_disputeId) == 0) revert PrivateERC20ResolutionModule_NonExistentDispute();
    if (
      ORACLE.disputeStatus(_disputeId) != IOracle.DisputeStatus.None
        && ORACLE.disputeStatus(_disputeId) != IOracle.DisputeStatus.Escalated
    ) {
      revert PrivateERC20ResolutionModule_AlreadyResolved();
    }

    Escalation memory _escalation = escalations[_disputeId];
    if (_escalation.startTime == 0) revert PrivateERC20ResolutionModule_DisputeNotEscalated();

    RequestParameters memory _params = decodeRequestData(_request.resolutionModuleData);

    if (block.timestamp < _escalation.startTime + _params.committingTimeWindow) {
      revert PrivateERC20ResolutionModule_OnGoingCommittingPhase();
    }
    if (block.timestamp <= _escalation.startTime + _params.committingTimeWindow + _params.revealingTimeWindow) {
      revert PrivateERC20ResolutionModule_OnGoingRevealingPhase();
    }

    uint256 _quorumReached = _escalation.totalVotes >= _params.minVotesForQuorum ? 1 : 0;

    if (_quorumReached == 1) {
      ORACLE.updateDisputeStatus(_request, _response, _dispute, IOracle.DisputeStatus.Won);
      emit DisputeResolved(_dispute.requestId, _disputeId, IOracle.DisputeStatus.Won);
    } else {
      ORACLE.updateDisputeStatus(_request, _response, _dispute, IOracle.DisputeStatus.Lost);
      emit DisputeResolved(_dispute.requestId, _disputeId, IOracle.DisputeStatus.Lost);
    }

    address _voter;
    uint256 _votersLength = _voters[_disputeId].length();
    for (uint256 _i; _i < _votersLength;) {
      _voter = _voters[_disputeId].at(_i);
      _params.votingToken.safeTransfer(_voter, _votersData[_disputeId][_voter].numOfVotes);
      unchecked {
        ++_i;
      }
    }
  }

  /// @inheritdoc IPrivateERC20ResolutionModule
  function computeCommitment(
    bytes32 _disputeId,
    uint256 _numberOfVotes,
    bytes32 _salt
  ) external view returns (bytes32 _commitment) {
    _commitment = keccak256(abi.encode(msg.sender, _disputeId, _numberOfVotes, _salt));
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
      && _params.minVotesForQuorum != 0 && _params.committingTimeWindow != 0 && _params.revealingTimeWindow != 0;
  }
}
