// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// solhint-disable-next-line no-unused-import
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {FixedPointMathLib} from 'solmate/utils/FixedPointMathLib.sol';

// solhint-disable-next-line no-unused-import
import {IResolutionModule} from
  '@defi-wonderland/prophet-core-contracts/solidity/interfaces/modules/resolution/IResolutionModule.sol';
import {Module, IModule} from '@defi-wonderland/prophet-core-contracts/solidity/contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';

import {IBondEscalationResolutionModule} from
  '../../../interfaces/modules/resolution/IBondEscalationResolutionModule.sol';

contract BondEscalationResolutionModule is Module, IBondEscalationResolutionModule {
  using SafeERC20 for IERC20;

  /// @inheritdoc IBondEscalationResolutionModule
  uint256 public constant BASE = 1e18;

  /// @inheritdoc IBondEscalationResolutionModule
  mapping(bytes32 _disputeId => Escalation _escalation) public escalations;

  /// @inheritdoc IBondEscalationResolutionModule
  mapping(bytes32 _disputeId => InequalityData _inequalityData) public inequalityData;

  /// @inheritdoc IBondEscalationResolutionModule
  mapping(bytes32 _disputeId => mapping(address _pledger => uint256 pledges)) public pledgesForDispute;

  /// @inheritdoc IBondEscalationResolutionModule
  mapping(bytes32 _disputeId => mapping(address _pledger => uint256 pledges)) public pledgesAgainstDispute;

  constructor(IOracle _oracle) Module(_oracle) {}

  /// @inheritdoc IModule
  function moduleName() external pure returns (string memory _moduleName) {
    return 'BondEscalationResolutionModule';
  }

  /// @inheritdoc IBondEscalationResolutionModule
  function decodeRequestData(bytes32 _requestId) public view returns (RequestParameters memory _params) {
    _params = abi.decode(requestData[_requestId], (RequestParameters));
  }

  /// @inheritdoc IResolutionModule
  function startResolution(bytes32 _disputeId) external onlyOracle {
    bytes32 _requestId = ORACLE.getDispute(_disputeId).requestId;
    escalations[_disputeId].startTime = uint128(block.timestamp);
    emit ResolutionStarted(_requestId, _disputeId);
  }

  /// @inheritdoc IBondEscalationResolutionModule
  function pledgeForDispute(bytes32 _requestId, bytes32 _disputeId, uint256 _pledgeAmount) external {
    Escalation storage _escalation = escalations[_disputeId];

    if (_escalation.startTime == 0) revert BondEscalationResolutionModule_NotEscalated();

    InequalityData storage _inequalityData = inequalityData[_disputeId];

    RequestParameters memory _params = decodeRequestData(_requestId);

    {
      uint256 _pledgingDeadline = _escalation.startTime + _params.timeUntilDeadline;

      if (block.timestamp >= _pledgingDeadline) revert BondEscalationResolutionModule_PledgingPhaseOver();

      // Revert if the inequality timer has passed
      if (_inequalityData.time != 0 && block.timestamp >= _inequalityData.time + _params.timeToBreakInequality) {
        revert BondEscalationResolutionModule_MustBeResolved();
      }

      if (_inequalityData.inequalityStatus == InequalityStatus.AgainstTurnToEqualize) {
        revert BondEscalationResolutionModule_AgainstTurnToEqualize();
      }
    }

    _escalation.pledgesFor += _pledgeAmount;
    pledgesForDispute[_disputeId][msg.sender] += _pledgeAmount;

    uint256 _updatedTotalVotes = _escalation.pledgesFor + _escalation.pledgesAgainst;

    _params.accountingExtension.pledge({
      _pledger: msg.sender,
      _requestId: _requestId,
      _disputeId: _disputeId,
      _token: _params.bondToken,
      _amount: _pledgeAmount
    });
    emit PledgedForDispute(msg.sender, _requestId, _disputeId, _pledgeAmount);

    if (_updatedTotalVotes >= _params.pledgeThreshold) {
      uint256 _updatedForVotes = _escalation.pledgesFor;
      uint256 _againstVotes = _escalation.pledgesAgainst;

      uint256 _newForVotesPercentage = FixedPointMathLib.mulDivDown(_updatedForVotes, BASE, _updatedTotalVotes);
      uint256 _againstVotesPercentage = FixedPointMathLib.mulDivDown(_againstVotes, BASE, _updatedTotalVotes);

      int256 _forPercentageDifference = int256(_newForVotesPercentage) - int256(_againstVotesPercentage);
      int256 _againstPercentageDifference = int256(_againstVotesPercentage) - int256(_newForVotesPercentage);

      int256 _scaledPercentageDiffAsInt = int256(_params.percentageDiff * BASE / 100);

      if (_againstPercentageDifference >= _scaledPercentageDiffAsInt) return;

      if (_forPercentageDifference >= _scaledPercentageDiffAsInt) {
        _inequalityData.inequalityStatus = InequalityStatus.AgainstTurnToEqualize;
        _inequalityData.time = block.timestamp;
      } else if (_inequalityData.inequalityStatus == InequalityStatus.ForTurnToEqualize) {
        // At this point, both _forPercentageDiff and _againstPercentageDiff are < _percentageDiff
        _inequalityData.inequalityStatus = InequalityStatus.Equalized;
        _inequalityData.time = 0;
      }
    }
  }

  /// @inheritdoc IBondEscalationResolutionModule
  function pledgeAgainstDispute(bytes32 _requestId, bytes32 _disputeId, uint256 _pledgeAmount) external {
    Escalation storage _escalation = escalations[_disputeId];

    if (_escalation.startTime == 0) revert BondEscalationResolutionModule_NotEscalated();

    InequalityData storage _inequalityData = inequalityData[_disputeId];

    RequestParameters memory _params = decodeRequestData(_requestId);

    {
      uint256 _pledgingDeadline = _escalation.startTime + _params.timeUntilDeadline;

      if (block.timestamp >= _pledgingDeadline) revert BondEscalationResolutionModule_PledgingPhaseOver();

      // Revert if the inequality timer has passed
      if (_inequalityData.time != 0 && block.timestamp >= _inequalityData.time + _params.timeToBreakInequality) {
        revert BondEscalationResolutionModule_MustBeResolved();
      }

      if (_inequalityData.inequalityStatus == InequalityStatus.ForTurnToEqualize) {
        revert BondEscalationResolutionModule_ForTurnToEqualize();
      }
    }

    _escalation.pledgesAgainst += _pledgeAmount;
    pledgesAgainstDispute[_disputeId][msg.sender] += _pledgeAmount;

    uint256 _updatedTotalVotes = _escalation.pledgesFor + _escalation.pledgesAgainst;

    _params.accountingExtension.pledge({
      _pledger: msg.sender,
      _requestId: _requestId,
      _disputeId: _disputeId,
      _token: _params.bondToken,
      _amount: _pledgeAmount
    });
    emit PledgedAgainstDispute(msg.sender, _requestId, _disputeId, _pledgeAmount);

    if (_updatedTotalVotes >= _params.pledgeThreshold) {
      uint256 _updatedAgainstVotes = _escalation.pledgesAgainst;
      uint256 _forVotes = _escalation.pledgesFor;

      uint256 _forVotesPercentage = FixedPointMathLib.mulDivDown(_forVotes, BASE, _updatedTotalVotes);
      uint256 _newAgainstVotesPercentage = FixedPointMathLib.mulDivDown(_updatedAgainstVotes, BASE, _updatedTotalVotes);
      int256 _forPercentageDifference = int256(_forVotesPercentage) - int256(_newAgainstVotesPercentage);
      int256 _againstPercentageDifference = int256(_newAgainstVotesPercentage) - int256(_forVotesPercentage);

      int256 _scaledPercentageDiffAsInt = int256(_params.percentageDiff * BASE / 100);

      if (_forPercentageDifference >= _scaledPercentageDiffAsInt) return;

      if (_againstPercentageDifference >= _scaledPercentageDiffAsInt) {
        _inequalityData.inequalityStatus = InequalityStatus.ForTurnToEqualize;
        _inequalityData.time = block.timestamp;
      } else if (_inequalityData.inequalityStatus == InequalityStatus.AgainstTurnToEqualize) {
        // At this point, both _forPercentageDiff and _againstPercentageDiff are < _percentageDiff
        _inequalityData.inequalityStatus = InequalityStatus.Equalized;
        _inequalityData.time = 0;
      }
    }
  }

  /// @inheritdoc IResolutionModule
  function resolveDispute(bytes32 _disputeId) external onlyOracle {
    Escalation storage _escalation = escalations[_disputeId];

    if (_escalation.resolution != Resolution.Unresolved) revert BondEscalationResolutionModule_AlreadyResolved();
    if (_escalation.startTime == 0) revert BondEscalationResolutionModule_NotEscalated();

    bytes32 _requestId = ORACLE.getDispute(_disputeId).requestId;

    RequestParameters memory _params = decodeRequestData(_requestId);

    InequalityData storage _inequalityData = inequalityData[_disputeId];

    uint256 _inequalityTimerDeadline = _inequalityData.time + _params.timeToBreakInequality;

    uint256 _pledgingDeadline = _escalation.startTime + _params.timeUntilDeadline;

    // Revert if we have not yet reached the deadline and the timer has not passed
    if (block.timestamp < _pledgingDeadline && block.timestamp < _inequalityTimerDeadline) {
      revert BondEscalationResolutionModule_PledgingPhaseNotOver();
    }

    uint256 _pledgesFor = _escalation.pledgesFor;
    uint256 _pledgesAgainst = _escalation.pledgesAgainst;
    uint256 _totalPledges = _pledgesFor + _pledgesAgainst;

    IOracle.DisputeStatus _disputeStatus;

    if (_totalPledges < _params.pledgeThreshold || _pledgesFor == _pledgesAgainst) {
      _escalation.resolution = Resolution.NoResolution;
      _disputeStatus = IOracle.DisputeStatus.NoResolution;
    } else if (_pledgesFor > _pledgesAgainst) {
      _escalation.resolution = Resolution.DisputerWon;
      _disputeStatus = IOracle.DisputeStatus.Won;
    } else if (_pledgesAgainst > _pledgesFor) {
      _escalation.resolution = Resolution.DisputerLost;
      _disputeStatus = IOracle.DisputeStatus.Lost;
    }

    ORACLE.updateDisputeStatus(_disputeId, _disputeStatus);
    emit DisputeResolved(_requestId, _disputeId, _disputeStatus);
  }

  /// @inheritdoc IBondEscalationResolutionModule
  function claimPledge(bytes32 _requestId, bytes32 _disputeId) external {
    Escalation storage _escalation = escalations[_disputeId];

    if (_escalation.resolution == Resolution.Unresolved) revert BondEscalationResolutionModule_NotResolved();

    RequestParameters memory _params = decodeRequestData(_requestId);
    uint256 _pledgerBalanceBefore;
    uint256 _pledgerProportion;
    uint256 _amountToRelease;
    uint256 _reward;

    if (_escalation.resolution == Resolution.DisputerWon) {
      _pledgerBalanceBefore = pledgesForDispute[_disputeId][msg.sender];
      pledgesForDispute[_disputeId][msg.sender] -= _pledgerBalanceBefore;

      _pledgerProportion = FixedPointMathLib.mulDivDown(_pledgerBalanceBefore, BASE, _escalation.pledgesFor);
      _reward = FixedPointMathLib.mulDivDown(_escalation.pledgesAgainst, _pledgerProportion, BASE);
      _amountToRelease = _reward + _pledgerBalanceBefore;
      _params.accountingExtension.releasePledge({
        _requestId: _requestId,
        _disputeId: _disputeId,
        _pledger: msg.sender,
        _token: _params.bondToken,
        _amount: _amountToRelease
      });
      emit PledgeClaimed({
        _requestId: _requestId,
        _disputeId: _disputeId,
        _pledger: msg.sender,
        _token: _params.bondToken,
        _pledgeReleased: _amountToRelease,
        _resolution: Resolution.DisputerWon
      });
    } else if (_escalation.resolution == Resolution.DisputerLost) {
      _pledgerBalanceBefore = pledgesAgainstDispute[_disputeId][msg.sender];
      pledgesAgainstDispute[_disputeId][msg.sender] -= _pledgerBalanceBefore;

      _pledgerProportion = FixedPointMathLib.mulDivDown(_pledgerBalanceBefore, BASE, _escalation.pledgesAgainst);
      _reward = FixedPointMathLib.mulDivDown(_escalation.pledgesFor, _pledgerProportion, BASE);
      _amountToRelease = _reward + _pledgerBalanceBefore;
      _params.accountingExtension.releasePledge({
        _requestId: _requestId,
        _disputeId: _disputeId,
        _pledger: msg.sender,
        _token: _params.bondToken,
        _amount: _amountToRelease
      });
      emit PledgeClaimed({
        _requestId: _requestId,
        _disputeId: _disputeId,
        _pledger: msg.sender,
        _token: _params.bondToken,
        _pledgeReleased: _amountToRelease,
        _resolution: Resolution.DisputerLost
      });
    } else if (_escalation.resolution == Resolution.NoResolution) {
      uint256 _pledgerBalanceFor = pledgesForDispute[_disputeId][msg.sender];
      uint256 _pledgerBalanceAgainst = pledgesAgainstDispute[_disputeId][msg.sender];

      if (_pledgerBalanceFor > 0) {
        pledgesForDispute[_disputeId][msg.sender] -= _pledgerBalanceFor;
        _params.accountingExtension.releasePledge({
          _requestId: _requestId,
          _disputeId: _disputeId,
          _pledger: msg.sender,
          _token: _params.bondToken,
          _amount: _pledgerBalanceFor
        });
        emit PledgeClaimed({
          _requestId: _requestId,
          _disputeId: _disputeId,
          _pledger: msg.sender,
          _token: _params.bondToken,
          _pledgeReleased: _pledgerBalanceFor,
          _resolution: Resolution.NoResolution
        });
      }

      if (_pledgerBalanceAgainst > 0) {
        pledgesAgainstDispute[_disputeId][msg.sender] -= _pledgerBalanceAgainst;
        _params.accountingExtension.releasePledge({
          _requestId: _requestId,
          _disputeId: _disputeId,
          _pledger: msg.sender,
          _token: _params.bondToken,
          _amount: _pledgerBalanceAgainst
        });
        emit PledgeClaimed({
          _requestId: _requestId,
          _disputeId: _disputeId,
          _pledger: msg.sender,
          _token: _params.bondToken,
          _pledgeReleased: _pledgerBalanceAgainst,
          _resolution: Resolution.NoResolution
        });
      }
    }
  }
}
