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
  function decodeRequestData(bytes calldata _data) public pure returns (RequestParameters memory _params) {
    _params = abi.decode(_data, (RequestParameters));
  }

  /// @inheritdoc IResolutionModule
  function startResolution(
    bytes32 _disputeId,
    IOracle.Request calldata,
    IOracle.Response calldata,
    IOracle.Dispute calldata _dispute
  ) external onlyOracle {
    escalations[_disputeId].startTime = uint128(block.timestamp);
    emit ResolutionStarted(_dispute.requestId, _disputeId);
  }

  /// @inheritdoc IBondEscalationResolutionModule
  function pledgeForDispute(
    IOracle.Request calldata _request,
    IOracle.Dispute calldata _dispute,
    uint256 _pledgeAmount
  ) external {
    _pledge(_request, _dispute, _pledgeAmount, true);
  }

  /// @inheritdoc IBondEscalationResolutionModule
  function pledgeAgainstDispute(
    IOracle.Request calldata _request,
    IOracle.Dispute calldata _dispute,
    uint256 _pledgeAmount
  ) external {
    _pledge(_request, _dispute, _pledgeAmount, false);
  }

  /// @inheritdoc IResolutionModule
  function resolveDispute(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external onlyOracle {
    bytes32 _requestId = _dispute.requestId;

    Escalation storage _escalation = escalations[_disputeId];

    if (_escalation.resolution != Resolution.Unresolved) revert BondEscalationResolutionModule_AlreadyResolved();
    if (_escalation.startTime == 0) revert BondEscalationResolutionModule_NotEscalated();

    RequestParameters memory _params = decodeRequestData(_request.resolutionModuleData);
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

    ORACLE.updateDisputeStatus(_request, _response, _dispute, _disputeStatus);
    emit DisputeResolved(_requestId, _disputeId, _disputeStatus);
  }

  /// @inheritdoc IBondEscalationResolutionModule
  function claimPledge(IOracle.Request calldata _request, IOracle.Dispute calldata _dispute) external {
    bytes32 _disputeId = _getId(_dispute);
    bytes32 _requestId = _dispute.requestId;
    Escalation storage _escalation = escalations[_disputeId];

    if (_escalation.resolution == Resolution.Unresolved) revert BondEscalationResolutionModule_NotResolved();

    uint256 _pledgerBalanceBefore;
    uint256 _pledgerProportion;
    uint256 _amountToRelease;
    uint256 _reward;
    RequestParameters memory _params = decodeRequestData(_request.resolutionModuleData);

    if (_escalation.resolution == Resolution.DisputerWon) {
      _pledgerBalanceBefore = pledgesForDispute[_disputeId][msg.sender];
      pledgesForDispute[_disputeId][msg.sender] -= _pledgerBalanceBefore;
      _pledgerProportion = FixedPointMathLib.mulDivDown(_pledgerBalanceBefore, BASE, _escalation.pledgesFor);
      _reward = FixedPointMathLib.mulDivDown(_escalation.pledgesAgainst, _pledgerProportion, BASE);
      _amountToRelease = _reward + _pledgerBalanceBefore;
      _claimPledge({
        _requestId: _requestId,
        _disputeId: _disputeId,
        _amountToRelease: _amountToRelease,
        _resolution: _escalation.resolution,
        _params: _params
      });
    } else if (_escalation.resolution == Resolution.DisputerLost) {
      _pledgerBalanceBefore = pledgesAgainstDispute[_disputeId][msg.sender];
      pledgesAgainstDispute[_disputeId][msg.sender] -= _pledgerBalanceBefore;
      _pledgerProportion = FixedPointMathLib.mulDivDown(_pledgerBalanceBefore, BASE, _escalation.pledgesAgainst);
      _reward = FixedPointMathLib.mulDivDown(_escalation.pledgesFor, _pledgerProportion, BASE);
      _amountToRelease = _reward + _pledgerBalanceBefore;
      _claimPledge({
        _requestId: _requestId,
        _disputeId: _disputeId,
        _amountToRelease: _amountToRelease,
        _resolution: _escalation.resolution,
        _params: _params
      });
    } else if (_escalation.resolution == Resolution.NoResolution) {
      uint256 _pledgerBalanceFor = pledgesForDispute[_disputeId][msg.sender];
      uint256 _pledgerBalanceAgainst = pledgesAgainstDispute[_disputeId][msg.sender];

      if (_pledgerBalanceFor > 0) {
        pledgesForDispute[_disputeId][msg.sender] -= _pledgerBalanceFor;
        _claimPledge({
          _requestId: _requestId,
          _disputeId: _disputeId,
          _amountToRelease: _pledgerBalanceFor,
          _resolution: _escalation.resolution,
          _params: _params
        });
      }

      if (_pledgerBalanceAgainst > 0) {
        pledgesAgainstDispute[_disputeId][msg.sender] -= _pledgerBalanceAgainst;
        _claimPledge({
          _requestId: _requestId,
          _disputeId: _disputeId,
          _amountToRelease: _pledgerBalanceAgainst,
          _resolution: _escalation.resolution,
          _params: _params
        });
      }
    }
  }

  /**
   * @notice Pledges for or against a dispute
   *
   * @param _pledgeAmount The amount to pledge
   * @param _pledgingFor Whether the pledger is pledging for or against the dispute
   */
  function _pledge(
    IOracle.Request calldata _request,
    IOracle.Dispute calldata _dispute,
    uint256 _pledgeAmount,
    bool _pledgingFor
  ) internal {
    bytes32 _disputeId = _getId(_dispute);
    bytes32 _requestId = _dispute.requestId;
    Escalation storage _escalation = escalations[_disputeId];

    if (_escalation.startTime == 0) revert BondEscalationResolutionModule_NotEscalated();

    InequalityData storage _inequalityData = inequalityData[_disputeId];
    RequestParameters memory _params = decodeRequestData(_request.resolutionModuleData);

    uint256 _pledgingDeadline = _escalation.startTime + _params.timeUntilDeadline;

    if (block.timestamp >= _pledgingDeadline) revert BondEscalationResolutionModule_PledgingPhaseOver();

    // Revert if the inequality timer has passed
    if (_inequalityData.time != 0 && block.timestamp >= _inequalityData.time + _params.timeToBreakInequality) {
      revert BondEscalationResolutionModule_MustBeResolved();
    }

    _params.accountingExtension.pledge({
      _pledger: msg.sender,
      _requestId: _requestId,
      _disputeId: _disputeId,
      _token: _params.bondToken,
      _amount: _pledgeAmount
    });

    if (_pledgingFor) {
      if (_inequalityData.inequalityStatus == InequalityStatus.AgainstTurnToEqualize) {
        revert BondEscalationResolutionModule_AgainstTurnToEqualize();
      }

      _escalation.pledgesFor += _pledgeAmount;
      pledgesForDispute[_disputeId][msg.sender] += _pledgeAmount;
      emit PledgedForDispute(msg.sender, _requestId, _disputeId, _pledgeAmount);
    } else {
      if (_inequalityData.inequalityStatus == InequalityStatus.ForTurnToEqualize) {
        revert BondEscalationResolutionModule_ForTurnToEqualize();
      }

      _escalation.pledgesAgainst += _pledgeAmount;
      pledgesAgainstDispute[_disputeId][msg.sender] += _pledgeAmount;
      emit PledgedAgainstDispute(msg.sender, _requestId, _disputeId, _pledgeAmount);
    }

    if (_escalation.pledgesFor + _escalation.pledgesAgainst >= _params.pledgeThreshold) {
      _updateInequalityStatus({
        _inequalityData: _inequalityData,
        _pledgesFor: _escalation.pledgesFor,
        _pledgesAgainst: _escalation.pledgesAgainst,
        _percentageDiff: _params.percentageDiff,
        _pledgingFor: _pledgingFor
      });
    }
  }

  /**
   * @notice Updates the inequality status of the dispute, switching it from one side to the other if the percentage difference is reached
   *
   * @param _inequalityData The inequality data for the dispute
   * @param _pledgesFor The total amount of pledges for the dispute
   * @param _pledgesAgainst The total amount of pledges against the dispute
   * @param _percentageDiff The percentage difference between the two sides
   * @param _pledgingFor Whether the pledger is pledging for or against the dispute
   */
  function _updateInequalityStatus(
    InequalityData storage _inequalityData,
    uint256 _pledgesFor,
    uint256 _pledgesAgainst,
    uint256 _percentageDiff,
    bool _pledgingFor
  ) internal {
    uint256 _totalPledges = _pledgesFor + _pledgesAgainst;
    uint256 _pledgesForPercentage = FixedPointMathLib.mulDivDown(_pledgesFor, BASE, _totalPledges);
    uint256 _pledgesAgainstPercentage = FixedPointMathLib.mulDivDown(_pledgesAgainst, BASE, _totalPledges);

    int256 _forPercentageDifference = int256(_pledgesForPercentage) - int256(_pledgesAgainstPercentage);
    int256 _againstPercentageDifference = int256(_pledgesAgainstPercentage) - int256(_pledgesForPercentage);

    int256 _scaledPercentageDiffAsInt = int256(_percentageDiff * BASE / 100);

    if (_pledgingFor) {
      if (_againstPercentageDifference >= _scaledPercentageDiffAsInt) return;

      if (_forPercentageDifference >= _scaledPercentageDiffAsInt) {
        _inequalityData.inequalityStatus = InequalityStatus.AgainstTurnToEqualize;
        _inequalityData.time = block.timestamp;
      } else if (_inequalityData.inequalityStatus == InequalityStatus.ForTurnToEqualize) {
        // At this point, both _forPercentageDiff and _againstPercentageDiff are < _percentageDiff
        _inequalityData.inequalityStatus = InequalityStatus.Equalized;
        _inequalityData.time = 0;
      }
    } else {
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

  /**
   * @notice Releases the pledged funds to the pledger
   *
   * @param _requestId The ID of the request
   * @param _disputeId The ID of the dispute
   * @param _amountToRelease The amount to release
   * @param _resolution The resolution of the dispute
   */
  function _claimPledge(
    bytes32 _requestId,
    bytes32 _disputeId,
    uint256 _amountToRelease,
    Resolution _resolution,
    RequestParameters memory _params
  ) internal {
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
      _resolution: _resolution
    });
  }

  /// @inheritdoc IModule
  function validateParameters(bytes calldata _encodedParameters)
    external
    pure
    override(Module, IModule)
    returns (bool _valid)
  {
    RequestParameters memory _params = decodeRequestData(_encodedParameters);
    _valid = (
      address(_params.accountingExtension) == address(0) || address(_params.bondToken) == address(0)
        || _params.percentageDiff == 0 || _params.pledgeThreshold == 0 || _params.timeUntilDeadline == 0
        || _params.timeToBreakInequality == 0
    ) ? false : true;
  }
}
