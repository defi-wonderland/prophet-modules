// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../utils/Helpers.sol';

import {Oracle, IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/contracts/Oracle.sol';
import {
  AccountingExtension, IAccountingExtension, IERC20
} from '../../../contracts/extensions/AccountingExtension.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

contract ForTest_AccountingExtension is AccountingExtension {
  using EnumerableSet for EnumerableSet.AddressSet;

  constructor(IOracle _oracle) AccountingExtension(_oracle) {}

  function forTest_setBalanceOf(address _user, IERC20 _token, uint256 _amount) public {
    balanceOf[_user][_token] = _amount;
  }

  function forTest_setBondedBalanceOf(bytes32 _requestId, address _user, IERC20 _token, uint256 _amount) public {
    bondedAmountOf[_user][_token][_requestId] = _amount;
  }
}

/**
 * @title Accounting Extension Unit tests
 */
contract BaseTest is Test, Helpers {
  // The target contract
  ForTest_AccountingExtension public extension;
  // A mock oracle
  IOracle public oracle;
  // Mock deposit token
  IERC20 public token;
  // Mock sender
  address public sender = makeAddr('sender');

  // Events tested
  event Deposited(address indexed _depositor, IERC20 indexed _token, uint256 _amount);
  event Withdrew(address indexed _depositor, IERC20 indexed _token, uint256 _amount);
  event Paid(
    bytes32 indexed _requestId, address indexed _beneficiary, address indexed _payer, IERC20 _token, uint256 _amount
  );
  event Bonded(bytes32 indexed _requestId, address indexed _depositor, IERC20 indexed _token, uint256 _amount);
  event Released(bytes32 indexed _requestId, address indexed _depositor, IERC20 indexed _token, uint256 _amount);

  /**
   * @notice Deploy the target and mock oracle extension
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    token = IERC20(makeAddr('Token'));
    vm.etch(address(token), hex'069420');

    extension = new ForTest_AccountingExtension(oracle);
  }
}

contract AccountingExtension_Unit_DepositAndWithdraw is BaseTest {
  /**
   * @notice Test an ERC20 deposit
   */
  function test_depositERC20(uint256 _amount) public {
    // Mock and expect the ERC20 transfer
    _mockAndExpect(
      address(token), abi.encodeCall(IERC20.transferFrom, (sender, address(extension), _amount)), abi.encode(true)
    );

    // Expect the event
    vm.expectEmit(true, true, true, true, address(extension));
    emit Deposited(sender, token, _amount);

    vm.prank(sender);
    extension.deposit(token, _amount);

    // Check: balance of token deposit increased?
    assertEq(extension.balanceOf(sender, token), _amount);
  }

  /**
   * @notice Test withdrawing ERC20. Should update balance and emit event
   */
  function test_withdrawERC20(uint256 _amount, uint256 _initialBalance) public {
    vm.assume(_amount > 0);

    // Set the initial balance
    _initialBalance = bound(_initialBalance, _amount, type(uint256).max);
    extension.forTest_setBalanceOf(sender, token, _initialBalance);

    _mockAndExpect(address(token), abi.encodeCall(IERC20.transfer, (sender, _amount)), abi.encode(true));

    // Expect the event
    vm.expectEmit(true, true, true, true, address(extension));
    emit Withdrew(sender, token, _amount);

    vm.prank(sender);
    extension.withdraw(token, _amount);

    // Check: balance of token deposit decreased?
    assertEq(extension.balanceOf(sender, token), _initialBalance - _amount);
  }

  /**
   * @notice Should revert if balance is insufficient
   */
  function test_withdrawRevert(uint256 _amount, uint256 _initialBalance) public {
    vm.assume(_amount > 0);

    // Set the initial balance
    _initialBalance = bound(_initialBalance, 0, _amount - 1);
    extension.forTest_setBalanceOf(sender, token, _initialBalance);

    // Check: does it revert if balance is insufficient?
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);
    vm.prank(sender);
    extension.withdraw(token, _amount);
  }
}

contract AccountingExtension_Unit_Bond is BaseTest {
  /**
   * @notice Test bonding an amount (which is taken from the bonder balanceOf)
   */
  function test_updateBalance(
    bytes32 _requestId,
    uint256 _amount,
    uint256 _initialBalance,
    address _bonder,
    address _sender
  ) public {
    _amount = bound(_amount, 0, _initialBalance);

    vm.prank(_bonder);
    extension.approveModule(_sender);

    // Mock and expect the module calling validation
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _sender)), abi.encode(true));

    // Mock and expect the module checking for participant
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.isParticipant, (_requestId, _bonder)), abi.encode(true));

    // Set the initial balance
    extension.forTest_setBalanceOf(_bonder, token, _initialBalance);

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(extension));
    emit Bonded(_requestId, _bonder, token, _amount);

    vm.prank(_sender);
    extension.bond({_bonder: _bonder, _requestId: _requestId, _token: token, _amount: _amount});

    // Check: is the balanceOf decreased?
    assertEq(extension.balanceOf(_bonder, token), _initialBalance - _amount);

    // Check: is the bondedAmountOf increased?
    assertEq(extension.bondedAmountOf(_bonder, token, _requestId), _amount);
  }

  /**
   * @notice Test bonding reverting if balanceOf is less than the amount to bond
   */
  function test_revertIfInsufficientBalance(
    bytes32 _requestId,
    uint256 _amount,
    uint248 _initialBalance,
    address _bonder,
    address _sender
  ) public {
    _amount = bound(_amount, uint256(_initialBalance) + 1, type(uint256).max);

    vm.prank(_bonder);
    extension.approveModule(_sender);

    // Mock and expect the module calling validation
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _sender)), abi.encode(true));

    // Mock and expect the module checking for participant
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.isParticipant, (_requestId, _bonder)), abi.encode(true));

    // Set the initial balance
    extension.forTest_setBalanceOf(_bonder, token, _initialBalance);

    // Check: does it revert if balance is insufficient?
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);

    vm.prank(_sender);
    extension.bond({_bonder: _bonder, _requestId: _requestId, _token: token, _amount: _amount});
  }

  /**
   * @notice Test bonding reverting if balanceOf is less than the amount to bond
   */
  function test_revertIfDisallowedModuleCalling(
    bytes32 _requestId,
    uint256 _amount,
    address _bonder,
    address _sender
  ) public {
    // Mock and expect the module calling validation
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _sender)), abi.encode(false));

    // Check: does it revert if the module is not allowed?
    vm.expectRevert(IAccountingExtension.AccountingExtension_UnauthorizedModule.selector);

    vm.prank(_sender);
    extension.bond({_bonder: _bonder, _requestId: _requestId, _token: token, _amount: _amount});
  }

  /**
   * @notice Test bonding reverting if the module is not approved to bond the _bonder funds
   */
  function test_revertIfInsufficientAllowance(
    bytes32 _requestId,
    uint256 _amount,
    address _bonder,
    address _module
  ) public {
    // Mock and expect the module calling validation
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _module)), abi.encode(true));

    // Mock and expect the module checking for a participant
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.isParticipant, (_requestId, _bonder)), abi.encode(true));

    // Check: does it revert if the module is not approved?
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientAllowance.selector);

    vm.prank(_module);
    extension.bond({_bonder: _bonder, _requestId: _requestId, _token: token, _amount: _amount});
  }

  /**
   * @notice Test bonding reverting if the caller is not approved to bond the _bonder funds
   */
  function test_withCaller_revertIfInsufficientAllowance(
    bytes32 _requestId,
    uint256 _amount,
    address _bonder,
    address _sender
  ) public {
    // mock the module calling validation
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _sender)), abi.encode(true));

    // Mock and expect the module checking for a participant
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.isParticipant, (_requestId, _bonder)), abi.encode(true));

    // Check: does it revert if the caller is not approved?
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientAllowance.selector);

    vm.prank(_sender);
    extension.bond({_bonder: _bonder, _requestId: _requestId, _token: token, _amount: _amount, _sender: _sender});
  }
}

contract AccountingExtension_Unit_Pay is BaseTest {
  /**
   * @notice Test paying a receiver. Should update balance and emit event.
   */
  function test_payUpdateBalance(
    bytes32 _requestId,
    uint256 _amount,
    uint256 _initialBalance,
    address _payer,
    address _receiver,
    address _sender
  ) public {
    _amount = bound(_amount, 0, _initialBalance);

    // Mock and expect the module calling validation
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _sender)), abi.encode(true));

    // Mock and expect the module checking for participant
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.isParticipant, (_requestId, _payer)), abi.encode(true));

    // Mock and expect the module checking for participant
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.isParticipant, (_requestId, _receiver)), abi.encode(true));

    // Set the initial bonded balance
    extension.forTest_setBondedBalanceOf(_requestId, _payer, token, _initialBalance);

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(extension));
    emit Paid(_requestId, _receiver, _payer, token, _amount);

    vm.prank(_sender);
    extension.pay({_requestId: _requestId, _payer: _payer, _receiver: _receiver, _token: token, _amount: _amount});

    // Check: is the receiver's balance increased?
    assertEq(extension.balanceOf(_receiver, token), _amount);

    // Check: is the payer's balance decreased?
    assertEq(extension.bondedAmountOf(_payer, token, _requestId), _initialBalance - _amount);
  }

  /**
   * @notice Test if pay reverts if bonded funds are not enough
   */
  function test_payRevertInsufficientBond(
    bytes32 _requestId,
    uint256 _amount,
    uint248 _initialBalance,
    address _payer,
    address _receiver,
    address _sender
  ) public {
    _amount = bound(_amount, uint256(_initialBalance) + 1, type(uint256).max);

    // Mock and expect the module calling validation
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _sender)), abi.encode(true));

    // Mock and expect the module checking for participant
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.isParticipant, (_requestId, _payer)), abi.encode(true));

    // Mock and expect the module checking for participant
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.isParticipant, (_requestId, _receiver)), abi.encode(true));

    // Set the initial bonded balance
    extension.forTest_setBondedBalanceOf(_requestId, _payer, token, _initialBalance);

    // Check: does it revert if the payer has insufficient funds?
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);

    vm.prank(_sender);
    extension.pay({_requestId: _requestId, _payer: _payer, _receiver: _receiver, _token: token, _amount: _amount});
  }

  /**
   * @notice Test if pay reverts if the caller is not a allowed module (checked via the oracle)
   */
  function test_payRevertInvalidCallingModule(
    bytes32 _requestId,
    uint256 _amount,
    uint248 _initialBalance,
    address _payer,
    address _receiver,
    address _sender
  ) public {
    _amount = bound(_amount, uint256(_initialBalance) + 1, type(uint256).max);

    // Mock and expect the module calling validation
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _sender)), abi.encode(false));

    // Check: does it revert if the module calling is not approved?
    vm.expectRevert(IAccountingExtension.AccountingExtension_UnauthorizedModule.selector);

    vm.prank(_sender);
    extension.pay({_requestId: _requestId, _payer: _payer, _receiver: _receiver, _token: token, _amount: _amount});
  }
}

contract AccountingExtension_Unit_Release is BaseTest {
  /**
   * @notice Test releasing an amount (which is added to the bonder balanceOf)
   */
  function test_releaseUpdateBalance(
    bytes32 _requestId,
    uint256 _amount,
    uint256 _initialBalance,
    address _bonder,
    address _sender
  ) public {
    _amount = bound(_amount, 0, _initialBalance);

    // Mock and expect the module calling validation
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _sender)), abi.encode(true));

    // Mock and expect the module checking for participant
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.isParticipant, (_requestId, _bonder)), abi.encode(true));

    // Set the initial bonded balance
    extension.forTest_setBondedBalanceOf(_requestId, _bonder, token, _initialBalance);

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(extension));
    emit Released(_requestId, _bonder, token, _amount);

    vm.prank(_sender);
    extension.release({_bonder: _bonder, _requestId: _requestId, _token: token, _amount: _amount});

    // Check: is the balance increased?
    assertEq(extension.balanceOf(_bonder, token), _amount);

    // check: is the bonded balance decreased?
    assertEq(extension.bondedAmountOf(_bonder, token, _requestId), _initialBalance - _amount);
  }

  /**
   * @notice Test releasing reverting if bondedAmountOf is less than the amount to release
   */
  function test_releaseInsufficientBalance(
    bytes32 _requestId,
    uint256 _amount,
    uint248 _initialBalance,
    address _bonder,
    address _sender
  ) public {
    _amount = bound(_amount, uint256(_initialBalance) + 1, type(uint256).max);

    // Mock and expect the module calling validation
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _sender)), abi.encode(true));

    // Mock and expect the module checking for participant
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.isParticipant, (_requestId, _bonder)), abi.encode(true));

    // Set the initial bonded balance
    extension.forTest_setBondedBalanceOf(_requestId, _bonder, token, _initialBalance);

    // Check: does it revert if calling with insufficient balance?
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);

    vm.prank(_sender);
    extension.release({_bonder: _bonder, _requestId: _requestId, _token: token, _amount: _amount});
  }

  /**
   * @notice Test releasing reverting if the caller is not a allowed module
   */
  function test_releaseDisallowedModuleCalling(
    bytes32 _requestId,
    uint256 _amount,
    address _bonder,
    address _sender
  ) public {
    // Mock and expect the module calling validation
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _sender)), abi.encode(false));

    // Check: does it revert if the module is not approved?
    vm.expectRevert(IAccountingExtension.AccountingExtension_UnauthorizedModule.selector);

    vm.prank(_sender);
    extension.release({_bonder: _bonder, _requestId: _requestId, _token: token, _amount: _amount});
  }
}

contract AccountingExtension_Unit_Approvals is BaseTest {
  /**
   * @notice Test approving modules / callers
   */
  function test_approvedModules(address _user, uint8 _modulesAmount) public {
    // Approve all modules from the array and storing them in memory
    address[] memory _modules = new address[](_modulesAmount);
    for (uint256 _i; _i < _modulesAmount; _i++) {
      address _module = vm.addr(_i + 1);
      _modules[_i] = _module;
      vm.prank(_user);
      extension.approveModule(_module);
    }

    // Check: does the approved modules equals the modules stored in the array?
    assertEq(_modules, extension.approvedModules(_user));
  }

  /**
   * @notice Test revoking approvals.
   */
  function test_revokeModules(address _user, address _module) public {
    // Approve a module
    vm.prank(_user);
    extension.approveModule(_module);

    // Create an array with just the approved module
    address[] memory _approvedModules = new address[](1);
    _approvedModules[0] = _module;

    // Check: does the returned approved modules match?
    assertEq(_approvedModules, extension.approvedModules(_user));

    vm.prank(_user);
    extension.revokeModule(_module);

    // Check: does it return an empty array after revoking the module?
    address[] memory _emptyArray = new address[](0);
    assertEq(_emptyArray, extension.approvedModules(_user));
  }
}
