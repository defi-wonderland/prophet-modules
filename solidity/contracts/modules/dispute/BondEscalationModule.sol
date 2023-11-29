// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

// solhint-disable-next-line no-unused-import
import {Module, IModule} from '@defi-wonderland/prophet-core-contracts/solidity/contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {FixedPointMathLib} from 'solmate/utils/FixedPointMathLib.sol';

import {IBondEscalationModule} from '../../../interfaces/modules/dispute/IBondEscalationModule.sol';

contract BondEscalationModule is Module, IBondEscalationModule {
  /// @inheritdoc IBondEscalationModule
  mapping(bytes32 _requestId => mapping(address _pledger => uint256 pledges)) public pledgesForDispute;

  /// @inheritdoc IBondEscalationModule
  mapping(bytes32 _requestId => mapping(address _pledger => uint256 pledges)) public pledgesAgainstDispute;

  /**
   * @notice Struct containing all the data for a given escalation.
   */
  mapping(bytes32 _requestId => BondEscalation) internal _escalations;

  constructor(IOracle _oracle) Module(_oracle) {}

  /// @inheritdoc IModule
  function moduleName() external pure returns (string memory _moduleName) {
    return 'BondEscalationModule';
  }

  /// @inheritdoc IBondEscalationModule
  function disputeResponse(
    IOracle.Request calldata _request,
    IOracle.Response calldata, /* _response */
    IOracle.Dispute calldata _dispute
  ) external onlyOracle {
    RequestParameters memory _params = decodeRequestData(_request.disputeModuleData);

    if (block.timestamp > ORACLE.createdAt(_dispute.responseId) + _params.disputeWindow) {
      revert BondEscalationModule_DisputeWindowOver();
    }

    BondEscalation storage _escalation = _escalations[_dispute.requestId];
    bytes32 _disputeId = _getId(_dispute);

    // Only the first dispute of a request should go through the bond escalation
    // Consecutive disputes should be handled by the resolution module
    if (_escalation.status == BondEscalationStatus.None) {
      if (block.timestamp > _params.bondEscalationDeadline) revert BondEscalationModule_BondEscalationOver();

      _escalation.status = BondEscalationStatus.Active;
      _escalation.disputeId = _disputeId;
      emit BondEscalationStatusUpdated(_dispute.requestId, _disputeId, BondEscalationStatus.Active);
    }

    _params.accountingExtension.bond({
      _bonder: _dispute.disputer,
      _requestId: _dispute.requestId,
      _token: _params.bondToken,
      _amount: _params.bondSize
    });

    emit ResponseDisputed({
      _requestId: _dispute.requestId,
      _responseId: _dispute.responseId,
      _disputeId: _disputeId,
      _dispute: _dispute,
      _blockNumber: block.number
    });
  }

  /// @inheritdoc IBondEscalationModule
  function onDisputeStatusChange(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Response calldata,
    IOracle.Dispute calldata _dispute
  ) external onlyOracle {
    RequestParameters memory _params = decodeRequestData(_request.disputeModuleData);

    BondEscalation storage _escalation = _escalations[_dispute.requestId];

    if (ORACLE.disputeStatus(_disputeId) == IOracle.DisputeStatus.Escalated) {
      if (_disputeId == _escalation.disputeId) {
        if (block.timestamp <= _params.bondEscalationDeadline) revert BondEscalationModule_BondEscalationNotOver();

        if (
          _escalation.status != BondEscalationStatus.Active
            || _escalation.amountOfPledgesForDispute != _escalation.amountOfPledgesAgainstDispute
        ) {
          revert BondEscalationModule_NotEscalatable();
        }

        _escalation.status = BondEscalationStatus.Escalated;
        emit BondEscalationStatusUpdated(_dispute.requestId, _disputeId, BondEscalationStatus.Escalated);
        return;
      }
    }

    bool _won = ORACLE.disputeStatus(_disputeId) == IOracle.DisputeStatus.Won;

    _params.accountingExtension.pay({
      _requestId: _dispute.requestId,
      _payer: _won ? _dispute.proposer : _dispute.disputer,
      _receiver: _won ? _dispute.disputer : _dispute.proposer,
      _token: _params.bondToken,
      _amount: _params.bondSize
    });

    if (_won) {
      _params.accountingExtension.release({
        _requestId: _dispute.requestId,
        _bonder: _dispute.disputer,
        _token: _params.bondToken,
        _amount: _params.bondSize
      });
    }

    if (_disputeId == _escalation.disputeId) {
      // The dispute has been escalated to the Resolution module
      if (_escalation.status == BondEscalationStatus.Escalated) {
        if (_escalation.amountOfPledgesAgainstDispute == 0) {
          return;
        }

        BondEscalationStatus _newStatus = _won ? BondEscalationStatus.DisputerWon : BondEscalationStatus.DisputerLost;
        _escalation.status = _newStatus;

        emit BondEscalationStatusUpdated(_dispute.requestId, _disputeId, _newStatus);

        _params.accountingExtension.onSettleBondEscalation({
          _requestId: _dispute.requestId,
          _disputeId: _disputeId,
          _forVotesWon: _won,
          _token: _params.bondToken,
          _amountPerPledger: _params.bondSize << 1,
          _winningPledgersLength: _won ? _escalation.amountOfPledgesForDispute : _escalation.amountOfPledgesAgainstDispute
        });
      } else {
        // The status has changed to Won or Lost
        uint256 _pledgesForDispute = _escalation.amountOfPledgesForDispute;
        uint256 _pledgesAgainstDispute = _escalation.amountOfPledgesAgainstDispute;
        bool _disputersWon = _pledgesForDispute > _pledgesAgainstDispute;

        uint256 _amountToPay = _disputersWon
          ? _params.bondSize + FixedPointMathLib.mulDivDown(_pledgesAgainstDispute, _params.bondSize, _pledgesForDispute)
          : _params.bondSize + FixedPointMathLib.mulDivDown(_pledgesForDispute, _params.bondSize, _pledgesAgainstDispute);

        _params.accountingExtension.onSettleBondEscalation({
          _requestId: _dispute.requestId,
          _disputeId: _escalation.disputeId,
          _forVotesWon: _disputersWon,
          _token: _params.bondToken,
          _amountPerPledger: _amountToPay,
          _winningPledgersLength: _disputersWon ? _pledgesForDispute : _pledgesAgainstDispute
        });
      }
    }

    IOracle.DisputeStatus _status = ORACLE.disputeStatus(_disputeId);
    emit DisputeStatusChanged({_disputeId: _disputeId, _dispute: _dispute, _status: _status});
  }

  ////////////////////////////////////////////////////////////////////
  //                Bond Escalation Exclusive Functions
  ////////////////////////////////////////////////////////////////////

  /// @inheritdoc IBondEscalationModule
  function pledgeForDispute(IOracle.Request calldata _request, IOracle.Dispute calldata _dispute) external {
    bytes32 _disputeId = _getId(_dispute);
    RequestParameters memory _params = _pledgeChecks(_disputeId, _request, _dispute, true);

    _escalations[_dispute.requestId].amountOfPledgesForDispute += 1;
    pledgesForDispute[_dispute.requestId][msg.sender] += 1;
    _params.accountingExtension.pledge({
      _pledger: msg.sender,
      _requestId: _dispute.requestId,
      _disputeId: _disputeId,
      _token: _params.bondToken,
      _amount: _params.bondSize
    });

    emit PledgedForDispute(_disputeId, msg.sender, _params.bondSize);
  }

  /// @inheritdoc IBondEscalationModule
  function pledgeAgainstDispute(IOracle.Request calldata _request, IOracle.Dispute calldata _dispute) external {
    bytes32 _disputeId = _getId(_dispute);
    RequestParameters memory _params = _pledgeChecks(_disputeId, _request, _dispute, false);

    _escalations[_dispute.requestId].amountOfPledgesAgainstDispute += 1;
    pledgesAgainstDispute[_dispute.requestId][msg.sender] += 1;
    _params.accountingExtension.pledge({
      _pledger: msg.sender,
      _requestId: _dispute.requestId,
      _disputeId: _disputeId,
      _token: _params.bondToken,
      _amount: _params.bondSize
    });

    emit PledgedAgainstDispute(_disputeId, msg.sender, _params.bondSize);
  }

  /// @inheritdoc IBondEscalationModule
  function settleBondEscalation(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external {
    bytes32 _requestId = _getId(_request);
    RequestParameters memory _params = decodeRequestData(_request.disputeModuleData);
    BondEscalation storage _escalation = _escalations[_requestId];

    if (block.timestamp <= _params.bondEscalationDeadline + _params.tyingBuffer) {
      revert BondEscalationModule_BondEscalationNotOver();
    }

    if (_escalation.status != BondEscalationStatus.Active) {
      revert BondEscalationModule_BondEscalationCantBeSettled();
    }

    uint256 _pledgesForDispute = _escalation.amountOfPledgesForDispute;
    uint256 _pledgesAgainstDispute = _escalation.amountOfPledgesAgainstDispute;

    if (_pledgesForDispute == _pledgesAgainstDispute) {
      revert BondEscalationModule_ShouldBeEscalated();
    }

    bool _disputersWon = _pledgesForDispute > _pledgesAgainstDispute;
    _escalation.status = _disputersWon ? BondEscalationStatus.DisputerWon : BondEscalationStatus.DisputerLost;

    emit BondEscalationStatusUpdated(_requestId, _escalation.disputeId, _escalation.status);

    ORACLE.updateDisputeStatus(
      _request, _response, _dispute, _disputersWon ? IOracle.DisputeStatus.Won : IOracle.DisputeStatus.Lost
    );
  }

  /**
   * @notice Checks the necessary conditions for pledging
   * @return _params The decoded parameters for the request
   */
  function _pledgeChecks(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Dispute calldata _dispute,
    bool _forDispute
  ) internal view returns (RequestParameters memory _params) {
    BondEscalation memory _escalation = _escalations[_dispute.requestId];

    if (_disputeId != _escalation.disputeId) {
      revert BondEscalationModule_InvalidDispute();
    }

    _params = decodeRequestData(_request.disputeModuleData);

    if (block.timestamp > _params.bondEscalationDeadline + _params.tyingBuffer) {
      revert BondEscalationModule_BondEscalationOver();
    }

    uint256 _numPledgersForDispute = _escalation.amountOfPledgesForDispute;
    uint256 _numPledgersAgainstDispute = _escalation.amountOfPledgesAgainstDispute;

    if (_forDispute) {
      if (_numPledgersForDispute == _params.maxNumberOfEscalations) {
        revert BondEscalationModule_MaxNumberOfEscalationsReached();
      }
      if (_numPledgersForDispute > _numPledgersAgainstDispute) revert BondEscalationModule_CanOnlySurpassByOnePledge();
    } else {
      if (_numPledgersAgainstDispute == _params.maxNumberOfEscalations) {
        revert BondEscalationModule_MaxNumberOfEscalationsReached();
      }
      if (_numPledgersAgainstDispute > _numPledgersForDispute) revert BondEscalationModule_CanOnlySurpassByOnePledge();
    }

    if (block.timestamp > _params.bondEscalationDeadline && _numPledgersForDispute == _numPledgersAgainstDispute) {
      revert BondEscalationModule_CannotBreakTieDuringTyingBuffer();
    }
  }

  ////////////////////////////////////////////////////////////////////
  //                        View Functions
  ////////////////////////////////////////////////////////////////////

  /// @inheritdoc IBondEscalationModule
  function decodeRequestData(bytes calldata _data) public pure returns (RequestParameters memory _params) {
    _params = abi.decode(_data, (RequestParameters));
  }

  /// @inheritdoc IBondEscalationModule
  function getEscalation(bytes32 _requestId) public view returns (BondEscalation memory _escalation) {
    _escalation = _escalations[_requestId];
  }
}
