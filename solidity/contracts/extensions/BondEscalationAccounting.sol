// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {AccountingExtension} from './AccountingExtension.sol';

import {IBondEscalationAccounting} from '../../interfaces/extensions/IBondEscalationAccounting.sol';
import {IBondEscalationModule} from '../../interfaces/modules/dispute/IBondEscalationModule.sol';

contract BondEscalationAccounting is AccountingExtension, IBondEscalationAccounting {
  /// @inheritdoc IBondEscalationAccounting
  mapping(bytes32 _disputeId => mapping(IERC20 _token => uint256 _amount)) public pledges;

  /// @inheritdoc IBondEscalationAccounting
  mapping(bytes32 _disputeId => EscalationResult _result) public escalationResults;

  /// @inheritdoc IBondEscalationAccounting
  mapping(bytes32 _requestId => mapping(address _pledger => bool _claimed)) public pledgerClaimed;

  /// @inheritdoc IBondEscalationAccounting
  mapping(address _caller => bool _authorized) public authorizedCallers;

  constructor(IOracle _oracle, address[] memory _authorizedCallers) AccountingExtension(_oracle) {
    uint256 _length = _authorizedCallers.length;
    for (uint256 _i; _i < _length; ++_i) {
      authorizedCallers[_authorizedCallers[_i]] = true;
    }
  }

  modifier onlyAuthorizedCaller() {
    if (!authorizedCallers[msg.sender]) revert BondEscalationAccounting_UnauthorizedCaller();
    _;
  }

  /// @inheritdoc IBondEscalationAccounting
  function pledge(
    address _pledger,
    IOracle.Request calldata _request,
    IOracle.Dispute calldata _dispute,
    IERC20 _token,
    uint256 _amount
  ) external onlyAuthorizedCaller {
    bytes32 _requestId = _getId(_request);
    bytes32 _disputeId = _validateDispute(_request, _dispute);

    if (!ORACLE.allowedModule(_requestId, msg.sender)) revert AccountingExtension_UnauthorizedModule();
    if (balanceOf[_pledger][_token] < _amount) revert BondEscalationAccounting_InsufficientFunds();

    pledges[_disputeId][_token] += _amount;

    unchecked {
      balanceOf[_pledger][_token] -= _amount;
    }

    emit Pledged({_pledger: _pledger, _requestId: _requestId, _disputeId: _disputeId, _token: _token, _amount: _amount});
  }

  /// @inheritdoc IBondEscalationAccounting
  function onSettleBondEscalation(
    IOracle.Request calldata _request,
    IOracle.Dispute calldata _dispute,
    IERC20 _token,
    uint256 _amountPerPledger,
    uint256 _winningPledgersLength
  ) external onlyAuthorizedCaller {
    bytes32 _requestId = _getId(_request);
    bytes32 _disputeId = _validateDispute(_request, _dispute);

    if (!ORACLE.allowedModule(_requestId, msg.sender)) revert AccountingExtension_UnauthorizedModule();

    if (pledges[_disputeId][_token] < _amountPerPledger * _winningPledgersLength) {
      revert BondEscalationAccounting_InsufficientFunds();
    }

    if (escalationResults[_disputeId].requestId != bytes32(0)) {
      revert BondEscalationAccounting_AlreadySettled();
    }

    escalationResults[_disputeId] = EscalationResult({
      requestId: _requestId,
      token: _token,
      amountPerPledger: _amountPerPledger,
      bondEscalationModule: IBondEscalationModule(msg.sender)
    });

    emit BondEscalationSettled({
      _requestId: _requestId,
      _disputeId: _disputeId,
      _token: _token,
      _amountPerPledger: _amountPerPledger,
      _winningPledgersLength: _winningPledgersLength
    });
  }

  /// @inheritdoc IBondEscalationAccounting
  function claimEscalationReward(bytes32 _disputeId, address _pledger) external {
    EscalationResult memory _result = escalationResults[_disputeId];
    if (_result.token == IERC20(address(0))) revert BondEscalationAccounting_NoEscalationResult();
    bytes32 _requestId = _result.requestId;
    if (pledgerClaimed[_requestId][_pledger]) revert BondEscalationAccounting_AlreadyClaimed();

    IOracle.DisputeStatus _status = ORACLE.disputeStatus(_disputeId);
    uint256 _amountPerPledger = _result.amountPerPledger;
    uint256 _numberOfPledges;

    if (_status == IOracle.DisputeStatus.NoResolution) {
      _numberOfPledges = _result.bondEscalationModule.pledgesForDispute(_requestId, _pledger)
        + _result.bondEscalationModule.pledgesAgainstDispute(_requestId, _pledger);
    } else {
      _numberOfPledges = _status == IOracle.DisputeStatus.Won
        ? _result.bondEscalationModule.pledgesForDispute(_requestId, _pledger)
        : _result.bondEscalationModule.pledgesAgainstDispute(_requestId, _pledger);
    }

    IERC20 _token = _result.token;
    uint256 _claimAmount = _amountPerPledger * _numberOfPledges;

    pledgerClaimed[_requestId][_pledger] = true;
    balanceOf[_pledger][_token] += _claimAmount;

    unchecked {
      pledges[_disputeId][_token] -= _claimAmount;
    }

    emit EscalationRewardClaimed({
      _requestId: _requestId,
      _disputeId: _disputeId,
      _pledger: _pledger,
      _token: _result.token,
      _amount: _claimAmount
    });
  }

  /// @inheritdoc IBondEscalationAccounting
  function releasePledge(
    IOracle.Request calldata _request,
    IOracle.Dispute calldata _dispute,
    address _pledger,
    IERC20 _token,
    uint256 _amount
  ) external onlyAuthorizedCaller {
    bytes32 _requestId = _getId(_request);
    bytes32 _disputeId = _validateDispute(_request, _dispute);

    if (!ORACLE.allowedModule(_requestId, msg.sender)) revert AccountingExtension_UnauthorizedModule();

    if (pledges[_disputeId][_token] < _amount) revert BondEscalationAccounting_InsufficientFunds();

    balanceOf[_pledger][_token] += _amount;

    unchecked {
      pledges[_disputeId][_token] -= _amount;
    }

    emit PledgeReleased({
      _requestId: _requestId,
      _disputeId: _disputeId,
      _pledger: _pledger,
      _token: _token,
      _amount: _amount
    });
  }
}
