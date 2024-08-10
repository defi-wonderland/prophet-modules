// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {
  BondEscalationAccounting,
  IBondEscalationAccounting
} from '../../../../contracts/extensions/BondEscalationAccounting.sol';
import {IBondEscalationModule, IOracle} from '../../../../contracts/modules/dispute/BondEscalationModule.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';

import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';

contract ForTest_BondEscalationAccounting is BondEscalationAccounting {
  constructor(IOracle _oracle) BondEscalationAccounting(_oracle) {}

  function forTest_setPledge(bytes32 _disputeId, IERC20 _token, uint256 _amount) public {
    pledges[_disputeId][_token] = _amount;
  }

  function forTest_setBalanceOf(address _bonder, IERC20 _token, uint256 _balance) public {
    balanceOf[_bonder][_token] = _balance;
  }

  function forTest_setBondedAmountOf(address _bonder, IERC20 _token, bytes32 _requestId, uint256 _amount) public {
    bondedAmountOf[_bonder][_token][_requestId] = _amount;
  }

  function forTest_setClaimed(address _pledger, bytes32 _requestId, bool _claimed) public {
    pledgerClaimed[_requestId][_pledger] = _claimed;
  }

  function forTest_setEscalationResult(
    bytes32 _disputeId,
    bytes32 _requestId,
    IERC20 _token,
    uint256 _amountPerPledger,
    IBondEscalationModule _bondEscalationModule
  ) public {
    escalationResults[_disputeId] = EscalationResult({
      requestId: _requestId,
      token: _token,
      amountPerPledger: _amountPerPledger,
      bondEscalationModule: _bondEscalationModule
    });
  }
}

/**
 * @title Bonded Response Module Unit tests
 */
contract BaseTest is Test, Helpers {
  // The target contract
  ForTest_BondEscalationAccounting public bondEscalationAccounting;
  // A mock oracle
  IOracle public oracle;
  // A mock token
  IERC20 public token;
  // Mock EOA bonder
  address public bonder = makeAddr('bonder');
  address public pledger = makeAddr('pledger');

  // Pledged Event
  event Pledged(
    address indexed _pledger, bytes32 indexed _requestId, bytes32 indexed _disputeId, IERC20 _token, uint256 _amount
  );

  event BondEscalationSettled(
    bytes32 _requestId, bytes32 _disputeId, IERC20 _token, uint256 _amountPerPledger, uint256 _winningPledgersLength
  );

  event EscalationRewardClaimed(
    bytes32 indexed _requestId, bytes32 indexed _disputeId, address indexed _pledger, IERC20 _token, uint256 _amount
  );

  event PledgeReleased(
    bytes32 indexed _requestId, bytes32 indexed _disputeId, address indexed _pledger, IERC20 _token, uint256 _amount
  );

  function _createWinningPledgersArray(
    uint256 _numWinningPledgers
  ) internal returns (address[] memory _winningPledgers) {
    _winningPledgers = new address[](_numWinningPledgers);
    address _winningPledger;

    for (uint256 _i; _i < _numWinningPledgers; _i++) {
      _winningPledger = makeAddr(string.concat('winningPledger', Strings.toString(_i)));
      _winningPledgers[_i] = _winningPledger;
    }
  }

  /**
   * @notice Deploy the target and mock oracle+accounting extension
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    token = IERC20(makeAddr('ERC20'));
    vm.etch(address(token), hex'069420');

    bondEscalationAccounting = new ForTest_BondEscalationAccounting(oracle);
  }
}

contract BondEscalationAccounting_Unit_Pledge is BaseTest {
  function test_revertIfDisallowedModule(address _pledger, uint256 _amount) public {
    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);

    // Mock and expect the call to oracle checking if the module is allowed
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_getId(mockRequest), address(this))), abi.encode(false)
    );

    // Check: does it revert if called by an unauthorized module?
    vm.expectRevert(IAccountingExtension.AccountingExtension_UnauthorizedModule.selector);

    bondEscalationAccounting.pledge({
      _pledger: _pledger,
      _request: mockRequest,
      _dispute: _dispute,
      _token: token,
      _amount: _amount
    });
  }

  function test_revertIfNotEnoughDeposited(address _pledger, uint256 _amount) public {
    vm.assume(_amount > 0);

    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, address(this))), abi.encode(true)
    );

    // Check: does it revert if the pledger doesn't have enough deposited?
    vm.expectRevert(IBondEscalationAccounting.BondEscalationAccounting_InsufficientFunds.selector);

    bondEscalationAccounting.pledge({
      _pledger: _pledger,
      _request: mockRequest,
      _dispute: _dispute,
      _token: token,
      _amount: _amount
    });
  }

  function test_successfulCall(address _pledger, uint256 _amount) public {
    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect the call to oracle checking if the module is allowed
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, address(this))), abi.encode(true)
    );

    bondEscalationAccounting.forTest_setBalanceOf(_pledger, token, _amount);

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationAccounting));
    emit Pledged(_pledger, _requestId, _disputeId, token, _amount);

    uint256 _balanceBeforePledge = bondEscalationAccounting.balanceOf(_pledger, token);
    uint256 _pledgesBeforePledge = bondEscalationAccounting.pledges(_disputeId, token);

    bondEscalationAccounting.pledge({
      _pledger: _pledger,
      _request: mockRequest,
      _dispute: _dispute,
      _token: token,
      _amount: _amount
    });

    uint256 _balanceAfterPledge = bondEscalationAccounting.balanceOf(_pledger, token);
    uint256 _pledgesAfterPledge = bondEscalationAccounting.pledges(_disputeId, token);

    // Check: is the balance before decreased?
    assertEq(_balanceAfterPledge, _balanceBeforePledge - _amount);
    // Check: is the balance after increased?
    assertEq(_pledgesAfterPledge, _pledgesBeforePledge + _amount);
  }
}

contract BondEscalationAccounting_Unit_OnSettleBondEscalation is BaseTest {
  function test_revertIfDisallowedModule(uint256 _numOfWinningPledgers, uint256 _amountPerPledger) public {
    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);

    // Mock and expect the call to oracle checking if the module is allowed
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, address(this))), abi.encode(false)
    );

    // Check: does it revert if the module is not allowed?
    vm.expectRevert(IAccountingExtension.AccountingExtension_UnauthorizedModule.selector);

    bondEscalationAccounting.onSettleBondEscalation({
      _request: mockRequest,
      _dispute: _dispute,
      _token: token,
      _amountPerPledger: _amountPerPledger,
      _winningPledgersLength: _numOfWinningPledgers
    });
  }

  function test_revertIfAlreadySettled(uint256 _numOfWinningPledgers, uint256 _amountPerPledger) public {
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(mockDispute);

    vm.assume(_amountPerPledger > 0);
    vm.assume(_numOfWinningPledgers > 0);
    vm.assume(_amountPerPledger < type(uint256).max / _numOfWinningPledgers);

    // Mock and expect the call to oracle checking if the module is allowed
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, address(this))), abi.encode(true)
    );

    // Mock and expect the call to oracle checking if the dispute exists
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));

    bondEscalationAccounting.forTest_setEscalationResult(
      _disputeId, _requestId, token, _amountPerPledger, IBondEscalationModule(address(this))
    );

    bondEscalationAccounting.forTest_setPledge(_disputeId, token, _amountPerPledger * _numOfWinningPledgers);

    // Check: does it revert if the escalation is already settled?
    vm.expectRevert(IBondEscalationAccounting.BondEscalationAccounting_AlreadySettled.selector);

    bondEscalationAccounting.onSettleBondEscalation({
      _request: mockRequest,
      _dispute: mockDispute,
      _token: token,
      _amountPerPledger: _amountPerPledger,
      _winningPledgersLength: _numOfWinningPledgers
    });
  }

  function test_revertIfInsufficientFunds(uint256 _amountPerPledger, uint256 _numOfWinningPledgers) public {
    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    // Note, bounding to a max of 30 so that the tests doesn't take forever to run
    _numOfWinningPledgers = bound(_numOfWinningPledgers, 1, 30);
    _amountPerPledger = bound(_amountPerPledger, 1, type(uint256).max / _numOfWinningPledgers);

    // Mock and expect the call to oracle checking if the module is allowed
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, address(this))), abi.encode(true)
    );

    address[] memory _winningPledgers = _createWinningPledgersArray(_numOfWinningPledgers);

    uint256 _totalAmountToPay = _amountPerPledger * _winningPledgers.length;
    uint256 _insufficientPledges = _totalAmountToPay - 1;

    bondEscalationAccounting.forTest_setPledge(_disputeId, token, _insufficientPledges);

    // Check: does it revert if the pledger does not have enough funds?
    vm.expectRevert(IBondEscalationAccounting.BondEscalationAccounting_InsufficientFunds.selector);

    bondEscalationAccounting.onSettleBondEscalation({
      _request: mockRequest,
      _dispute: _dispute,
      _token: token,
      _amountPerPledger: _amountPerPledger,
      _winningPledgersLength: _numOfWinningPledgers
    });
  }

  function test_successfulCall(uint256 _numOfWinningPledgers, uint256 _amountPerPledger) public {
    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    // Note, bounding to a max of 30 so that the tests doesn't take forever to run
    _numOfWinningPledgers = bound(_numOfWinningPledgers, 1, 30);
    _amountPerPledger = bound(_amountPerPledger, 1, type(uint256).max / _numOfWinningPledgers);

    // Mock and expect the call to oracle checking if the module is allowed
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, address(this))), abi.encode(true)
    );

    address[] memory _winningPledgers = _createWinningPledgersArray(_numOfWinningPledgers);
    uint256 _totalAmountToPay = _amountPerPledger * _winningPledgers.length;

    bondEscalationAccounting.forTest_setPledge(_disputeId, token, _totalAmountToPay);

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationAccounting));
    emit BondEscalationSettled(_requestId, _disputeId, token, _amountPerPledger, _numOfWinningPledgers);

    bondEscalationAccounting.onSettleBondEscalation({
      _request: mockRequest,
      _dispute: _dispute,
      _token: token,
      _amountPerPledger: _amountPerPledger,
      _winningPledgersLength: _numOfWinningPledgers
    });

    (
      bytes32 _requestIdSaved,
      IERC20 _token,
      uint256 _amountPerPledgerSaved,
      IBondEscalationModule _bondEscalationModule
    ) = bondEscalationAccounting.escalationResults(_disputeId);

    // Check: are the escalation results properly stored?
    assertEq(_requestIdSaved, _requestId);
    assertEq(address(_token), address(token));
    assertEq(_amountPerPledgerSaved, _amountPerPledger);
    assertEq(address(_bondEscalationModule), address(this));
  }
}

contract BondEscalationAccounting_Unit_ReleasePledge is BaseTest {
  function test_revertIfDisallowedModule(address _pledger, uint256 _amount) public {
    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);

    // Mock and expect the call to oracle checking if the module is allowed
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, address(this))), abi.encode(false)
    );

    // Check: does it revert if the module is not authorized?
    vm.expectRevert(IAccountingExtension.AccountingExtension_UnauthorizedModule.selector);

    bondEscalationAccounting.releasePledge({
      _request: mockRequest,
      _dispute: _dispute,
      _pledger: _pledger,
      _token: token,
      _amount: _amount
    });
  }

  function test_revertIfInsufficientFunds(uint256 _amount, address _pledger) public {
    vm.assume(_amount < type(uint256).max);

    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect the call to oracle checking if the module is allowed
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, address(this))), abi.encode(true)
    );

    bondEscalationAccounting.forTest_setPledge(_disputeId, token, _amount);
    uint256 _underflowAmount = _amount + 1;

    // Check: does it revert if the pledger does not have enough funds pledged?
    vm.expectRevert(IBondEscalationAccounting.BondEscalationAccounting_InsufficientFunds.selector);

    bondEscalationAccounting.releasePledge({
      _request: mockRequest,
      _dispute: _dispute,
      _pledger: _pledger,
      _token: token,
      _amount: _underflowAmount
    });
  }

  function test_successfulCall(uint256 _amount, address _pledger) public {
    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect the call to oracle checking if the module is allowed
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, address(this))), abi.encode(true)
    );

    bondEscalationAccounting.forTest_setPledge(_disputeId, token, _amount);

    bondEscalationAccounting.releasePledge({
      _request: mockRequest,
      _dispute: _dispute,
      _pledger: _pledger,
      _token: token,
      _amount: _amount
    });

    // Check: are the pledger's funds released?
    assertEq(bondEscalationAccounting.balanceOf(_pledger, token), _amount);
  }

  function test_emitsEvent(uint256 _amount, address _pledger) public {
    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect the call to oracle checking if the module is allowed
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, address(this))), abi.encode(true)
    );

    bondEscalationAccounting.forTest_setPledge(_disputeId, token, _amount);

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationAccounting));
    emit PledgeReleased(_requestId, _disputeId, _pledger, token, _amount);

    bondEscalationAccounting.releasePledge({
      _request: mockRequest,
      _dispute: _dispute,
      _pledger: _pledger,
      _token: token,
      _amount: _amount
    });
  }
}

contract BondEscalationAccounting_Unit_ClaimEscalationReward is BaseTest {
  function test_revertIfInvalidEscalation(bytes32 _disputeId) public {
    // Check: does it revert if the escalation is not valid?
    vm.expectRevert(IBondEscalationAccounting.BondEscalationAccounting_NoEscalationResult.selector);

    bondEscalationAccounting.claimEscalationReward(_disputeId, pledger);
  }

  function test_revertIfAlreadyClaimed(bytes32 _disputeId, bytes32 _requestId) public {
    bondEscalationAccounting.forTest_setEscalationResult(
      _disputeId, _requestId, token, 0, IBondEscalationModule(address(this))
    );

    bondEscalationAccounting.forTest_setClaimed(pledger, _requestId, true);

    // Check: does it revert if the reward is already claimed?
    vm.expectRevert(IBondEscalationAccounting.BondEscalationAccounting_AlreadyClaimed.selector);

    bondEscalationAccounting.claimEscalationReward(_disputeId, pledger);
  }

  function test_forVotesWon(
    bytes32 _disputeId,
    bytes32 _requestId,
    uint256 _amount,
    uint256 _pledges,
    address _bondEscalationModule
  ) public assumeFuzzable(_bondEscalationModule) {
    vm.assume(_amount > 0);
    vm.assume(_pledges > 0);
    vm.assume(_amount < type(uint256).max / _pledges);

    bondEscalationAccounting.forTest_setEscalationResult(
      _disputeId, _requestId, token, _amount, IBondEscalationModule(_bondEscalationModule)
    );

    bondEscalationAccounting.forTest_setPledge(_disputeId, token, _amount * _pledges);

    // Mock and expect to call the oracle getting the dispute status
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Won)
    );

    // Mock and expect the call to the escalation module asking for pledges
    _mockAndExpect(
      _bondEscalationModule,
      abi.encodeCall(IBondEscalationModule.pledgesForDispute, (_requestId, pledger)),
      abi.encode(_pledges)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationAccounting));
    emit EscalationRewardClaimed(_requestId, _disputeId, pledger, token, _amount * _pledges);

    vm.prank(_bondEscalationModule);
    bondEscalationAccounting.claimEscalationReward(_disputeId, pledger);

    // Check: is the balance of the pledger properly updated?
    assertEq(bondEscalationAccounting.balanceOf(pledger, token), _amount * _pledges);
    // Check: is the reward marked as claimed for the pledger?
    assertTrue(bondEscalationAccounting.pledgerClaimed(_requestId, pledger));
    // Check: are the pledges updated?
    assertEq(bondEscalationAccounting.pledges(_disputeId, token), 0);
  }

  function test_againstVotesWon(
    bytes32 _disputeId,
    bytes32 _requestId,
    uint256 _amount,
    uint256 _pledges,
    address _bondEscalationModule
  ) public assumeFuzzable(_bondEscalationModule) {
    vm.assume(_amount > 0);
    vm.assume(_pledges > 0);

    _amount = bound(_amount, 0, type(uint256).max / _pledges);

    bondEscalationAccounting.forTest_setEscalationResult(
      _disputeId, _requestId, token, _amount, IBondEscalationModule(_bondEscalationModule)
    );

    bondEscalationAccounting.forTest_setPledge(_disputeId, token, _amount * _pledges);

    // Mock and expect to call the oracle getting the dispute status
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Lost)
    );

    // Mock and expect to call the escalation module asking for pledges
    _mockAndExpect(
      _bondEscalationModule,
      abi.encodeCall(IBondEscalationModule.pledgesAgainstDispute, (_requestId, pledger)),
      abi.encode(_pledges)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationAccounting));
    emit EscalationRewardClaimed(_requestId, _disputeId, pledger, token, _amount * _pledges);

    vm.prank(_bondEscalationModule);
    bondEscalationAccounting.claimEscalationReward(_disputeId, pledger);

    // Check: is the balance of the pledger properly updated?
    assertEq(bondEscalationAccounting.balanceOf(pledger, token), _amount * _pledges);
    // Check: is the reward marked as claimed for the pledger?
    assertTrue(bondEscalationAccounting.pledgerClaimed(_requestId, pledger));
    // Check: are the pledges updated?
    assertEq(bondEscalationAccounting.pledges(_disputeId, token), 0);
  }

  function test_noResolution(
    bytes32 _disputeId,
    bytes32 _requestId,
    uint256 _amount,
    uint256 _pledgesAgainst,
    uint256 _pledgesFor,
    address _bondEscalationModule
  ) public assumeFuzzable(_bondEscalationModule) {
    vm.assume(_amount > 0);
    vm.assume(_pledgesAgainst > 0 && _pledgesAgainst < 10_000);
    vm.assume(_pledgesFor > 0 && _pledgesFor < 10_000);

    _amount = bound(_amount, 0, type(uint128).max / (_pledgesAgainst + _pledgesFor));

    bondEscalationAccounting.forTest_setEscalationResult(
      _disputeId, _requestId, token, _amount, IBondEscalationModule(_bondEscalationModule)
    );

    bondEscalationAccounting.forTest_setPledge(_disputeId, token, _amount * (_pledgesAgainst + _pledgesFor));

    // Mock and expect to call the oracle getting the dispute status
    _mockAndExpect(
      address(oracle),
      abi.encodeCall(IOracle.disputeStatus, (_disputeId)),
      abi.encode(IOracle.DisputeStatus.NoResolution)
    );

    // Mock and expect to call the escalation module asking for pledges
    _mockAndExpect(
      _bondEscalationModule,
      abi.encodeCall(IBondEscalationModule.pledgesAgainstDispute, (_requestId, pledger)),
      abi.encode(_pledgesAgainst)
    );

    // Mock and expect the call to the escalation module asking for pledges
    _mockAndExpect(
      _bondEscalationModule,
      abi.encodeCall(IBondEscalationModule.pledgesForDispute, (_requestId, pledger)),
      abi.encode(_pledgesFor)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationAccounting));
    emit EscalationRewardClaimed(_requestId, _disputeId, pledger, token, _amount * (_pledgesAgainst + _pledgesFor));

    vm.prank(_bondEscalationModule);
    bondEscalationAccounting.claimEscalationReward(_disputeId, pledger);

    // Check: is the balance of the pledger properly updated?
    assertEq(bondEscalationAccounting.balanceOf(pledger, token), _amount * (_pledgesAgainst + _pledgesFor));
    // Check: is the reward marked as claimed for the pledger?
    assertTrue(bondEscalationAccounting.pledgerClaimed(_requestId, pledger));

    // Check: are the pledges updated?
    assertEq(bondEscalationAccounting.pledges(_disputeId, token), 0);
  }
}
