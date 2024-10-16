// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Validator} from '@defi-wonderland/prophet-core/solidity/contracts/Validator.sol';
import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import {IAccountingExtension} from '../../interfaces/extensions/IAccountingExtension.sol';

contract AccountingExtension is Validator, IAccountingExtension {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  /// @inheritdoc IAccountingExtension
  mapping(address _bonder => mapping(IERC20 _token => uint256 _balance)) public balanceOf;

  /// @inheritdoc IAccountingExtension
  mapping(address _bonder => mapping(IERC20 _token => mapping(bytes32 _requestId => uint256 _amount))) public
    bondedAmountOf;

  /**
   * @notice Storing which modules have the users approved to bond their tokens.
   */
  mapping(address _bonder => EnumerableSet.AddressSet _modules) internal _approvals;

  constructor(IOracle _oracle) Validator(_oracle) {}

  /**
   * @notice Checks that the caller is an allowed module used in the request.
   * @param _requestId The request ID.
   */
  modifier onlyAllowedModule(bytes32 _requestId) {
    if (!ORACLE.allowedModule(_requestId, msg.sender)) revert AccountingExtension_UnauthorizedModule();
    _;
  }

  /**
   * @notice Checks if the user is either the requester or a proposer, or a disputer.
   * @param _requestId The request ID.
   * @param _user The address to check.
   */
  modifier onlyParticipant(bytes32 _requestId, address _user) {
    if (!ORACLE.isParticipant(_requestId, _user)) revert AccountingExtension_UnauthorizedUser();
    _;
  }

  /// @inheritdoc IAccountingExtension
  function deposit(IERC20 _token, uint256 _amount) external {
    uint256 _balance = _token.balanceOf(address(this));

    _token.safeTransferFrom(msg.sender, address(this), _amount);

    if (_amount != _token.balanceOf(address(this)) - _balance) revert AccountingExtension_FeeOnTransferToken();

    balanceOf[msg.sender][_token] += _amount;

    emit Deposited(msg.sender, _token, _amount);
  }

  /// @inheritdoc IAccountingExtension
  function withdraw(IERC20 _token, uint256 _amount) external {
    uint256 _balance = balanceOf[msg.sender][_token];

    if (_balance < _amount) revert AccountingExtension_InsufficientFunds();

    unchecked {
      balanceOf[msg.sender][_token] -= _amount;
    }

    _token.safeTransfer(msg.sender, _amount);

    emit Withdrew(msg.sender, _token, _amount);
  }

  /// @inheritdoc IAccountingExtension
  function pay(
    bytes32 _requestId,
    address _payer,
    address _receiver,
    IERC20 _token,
    uint256 _amount
  ) external onlyAllowedModule(_requestId) onlyParticipant(_requestId, _payer) onlyParticipant(_requestId, _receiver) {
    if (bondedAmountOf[_payer][_token][_requestId] < _amount) {
      revert AccountingExtension_InsufficientFunds();
    }

    balanceOf[_receiver][_token] += _amount;

    unchecked {
      bondedAmountOf[_payer][_token][_requestId] -= _amount;
    }

    emit Paid({_requestId: _requestId, _beneficiary: _receiver, _payer: _payer, _token: _token, _amount: _amount});
  }

  /// @inheritdoc IAccountingExtension
  function bond(
    address _bonder,
    bytes32 _requestId,
    IERC20 _token,
    uint256 _amount
  ) external onlyAllowedModule(_requestId) onlyParticipant(_requestId, _bonder) {
    if (!_approvals[_bonder].contains(msg.sender)) revert AccountingExtension_NotAllowed();
    if (balanceOf[_bonder][_token] < _amount) revert AccountingExtension_InsufficientFunds();

    bondedAmountOf[_bonder][_token][_requestId] += _amount;

    unchecked {
      balanceOf[_bonder][_token] -= _amount;
    }

    emit Bonded(_requestId, _bonder, _token, _amount);
  }

  /// @inheritdoc IAccountingExtension
  function bond(
    address _bonder,
    bytes32 _requestId,
    IERC20 _token,
    uint256 _amount,
    address _sender
  ) external onlyAllowedModule(_requestId) onlyParticipant(_requestId, _bonder) {
    bool _moduleApproved = _approvals[_bonder].contains(msg.sender);
    bool _senderApproved = _approvals[_bonder].contains(_sender);

    if (!(_moduleApproved && _senderApproved)) {
      revert AccountingExtension_NotAllowed();
    }

    if (balanceOf[_bonder][_token] < _amount) revert AccountingExtension_InsufficientFunds();

    bondedAmountOf[_bonder][_token][_requestId] += _amount;

    unchecked {
      balanceOf[_bonder][_token] -= _amount;
    }

    emit Bonded(_requestId, _bonder, _token, _amount);
  }

  /// @inheritdoc IAccountingExtension
  function release(
    address _bonder,
    bytes32 _requestId,
    IERC20 _token,
    uint256 _amount
  ) external onlyAllowedModule(_requestId) onlyParticipant(_requestId, _bonder) {
    if (bondedAmountOf[_bonder][_token][_requestId] < _amount) revert AccountingExtension_InsufficientFunds();

    balanceOf[_bonder][_token] += _amount;

    unchecked {
      bondedAmountOf[_bonder][_token][_requestId] -= _amount;
    }

    emit Released(_requestId, _bonder, _token, _amount);
  }

  /// @inheritdoc IAccountingExtension
  function approveModule(address _module) external {
    _approvals[msg.sender].add(_module);
  }

  /// @inheritdoc IAccountingExtension
  function revokeModule(address _module) external {
    _approvals[msg.sender].remove(_module);
  }

  /// @inheritdoc IAccountingExtension
  function approvedModules(address _user) external view returns (address[] memory _approvedModules) {
    _approvedModules = _approvals[_user].values();
  }
}
