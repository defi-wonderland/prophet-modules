// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';
import {IOracle} from 'prophet-core-contracts/interfaces/IOracle.sol';
import {IModule} from 'prophet-core-contracts/interfaces/IModule.sol';

import {
  BondEscalationModule, IBondEscalationModule
} from '../../../../contracts/modules/dispute/BondEscalationModule.sol';

import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';
import {IBondEscalationAccounting} from '../../../../interfaces/extensions/IBondEscalationAccounting.sol';

/**
 * @dev Harness to set an entry in the requestData mapping, without triggering setup request hooks
 */
contract ForTest_BondEscalationModule is BondEscalationModule {
  constructor(IOracle _oracle) BondEscalationModule(_oracle) {}

  function forTest_setRequestData(bytes32 _requestId, bytes memory _data) public {
    requestData[_requestId] = _data;
  }

  function forTest_setBondEscalation(
    bytes32 _requestId,
    address[] memory _pledgersForDispute,
    address[] memory _pledgersAgainstDispute
  ) public {
    for (uint256 _i; _i < _pledgersForDispute.length; _i++) {
      pledgesForDispute[_requestId][_pledgersForDispute[_i]] += 1;
    }

    for (uint256 _i; _i < _pledgersAgainstDispute.length; _i++) {
      pledgesAgainstDispute[_requestId][_pledgersAgainstDispute[_i]] += 1;
    }

    _escalations[_requestId].amountOfPledgesForDispute += _pledgersForDispute.length;
    _escalations[_requestId].amountOfPledgesAgainstDispute += _pledgersAgainstDispute.length;
  }

  function forTest_setBondEscalationStatus(
    bytes32 _requestId,
    BondEscalationModule.BondEscalationStatus _bondEscalationStatus
  ) public {
    _escalations[_requestId].status = _bondEscalationStatus;
  }

  function forTest_setEscalatedDispute(bytes32 _requestId, bytes32 _disputeId) public {
    _escalations[_requestId].disputeId = _disputeId;
  }

  function forTest_setDisputeToRequest(bytes32 _disputeId, bytes32 _requestId) public {
    _disputeToRequest[_disputeId] = _requestId;
  }
}

/**
 * @title Bonded Response Module Unit tests
 */

contract BondEscalationModule_UnitTest is Test {
  // The target contract
  ForTest_BondEscalationModule public bondEscalationModule;

  // A mock oracle
  IOracle public oracle;

  // A mock accounting extension
  IBondEscalationAccounting public accounting;

  // A mock token
  IERC20 public token;

  // Mock EOA proposer
  address public proposer;

  // Mock EOA disputer
  address public disputer;

  // Mock bondSize
  uint256 public bondSize;

  // Mock max number of escalations
  uint256 public maxEscalations;

  // Mock bond escalation deadline
  uint256 public bondEscalationDeadline;

  // Mock tyingBuffer
  uint256 public tyingBuffer;

  // Mock dispute window
  uint256 public disputeWindow;

  // Events
  event PledgedInFavorOfDisputer(bytes32 indexed _disputeId, address indexed _pledger, uint256 indexed _amount);
  event PledgedInFavorOfProposer(bytes32 indexed _disputeId, address indexed _pledger, uint256 indexed _amount);
  event BondEscalationStatusUpdated(
    bytes32 indexed _requestId, bytes32 indexed _disputeId, IBondEscalationModule.BondEscalationStatus _status
  );
  event ResponseDisputed(bytes32 indexed _requestId, bytes32 _responseId, address _disputer, address _proposer);
  event DisputeStatusChanged(
    bytes32 indexed _requestId, bytes32 _responseId, address _disputer, address _proposer, IOracle.DisputeStatus _status
  );

  /**
   * @notice Deploy the target and mock oracle+accounting extension
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    accounting = IBondEscalationAccounting(makeAddr('BondEscalationAccounting'));
    vm.etch(address(accounting), hex'069420');

    token = IERC20(makeAddr('ERC20'));
    vm.etch(address(token), hex'069420');

    proposer = makeAddr('proposer');
    disputer = makeAddr('disputer');

    // Set to an arbitrary large value to avoid unintended reverts
    disputeWindow = type(uint128).max;

    // Avoid starting at 0 for time sensitive tests
    vm.warp(123_456);

    bondEscalationModule = new ForTest_BondEscalationModule(oracle);
  }

  ////////////////////////////////////////////////////////////////////
  //                    Tests for moduleName
  ////////////////////////////////////////////////////////////////////

  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleName() public {
    assertEq(bondEscalationModule.moduleName(), 'BondEscalationModule');
  }

  ////////////////////////////////////////////////////////////////////
  //                  Tests for escalateDispute
  ////////////////////////////////////////////////////////////////////

  /**
   * @notice Tests that escalateDispute reverts if the _disputeId doesn't match any existing disputes.
   */
  function test_escalateDisputeRevertOnInvalidDispute(bytes32 _disputeId) public {
    // Creates a fake dispute and mocks Oracle.getDispute to return it when called.
    _mockDispute(_disputeId, bytes32(0));

    // Expect Oracle.getDispute to be called.
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));

    // Expect the call to revert with DisputeDoesNotExist
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_DisputeDoesNotExist.selector);

    // Call disputeEscalated()
    vm.prank(address(oracle));
    bondEscalationModule.disputeEscalated(_disputeId);
  }

  /**
   * @notice Tests that escalateDispute reverts if the _disputeId doesn't match any existing disputes.
   */
  function test_revertOnInvalidParameters(
    bytes32 _requestId,
    uint256 _maxNumberOfEscalations,
    uint256 _bondSize,
    uint256 _bondEscalationDeadline,
    uint256 _tyingBuffer,
    uint256 _disputeWindow
  ) public {
    bytes memory _requestData = abi.encode(
      IBondEscalationModule.RequestParameters({
        accountingExtension: accounting,
        bondToken: token,
        bondSize: _bondSize,
        maxNumberOfEscalations: _maxNumberOfEscalations,
        bondEscalationDeadline: _bondEscalationDeadline,
        tyingBuffer: _tyingBuffer,
        disputeWindow: _disputeWindow
      })
    );

    if (_maxNumberOfEscalations == 0 || _bondSize == 0) {
      vm.expectRevert(IBondEscalationModule.BondEscalationModule_InvalidEscalationParameters.selector);
    }

    vm.prank(address(oracle));
    bondEscalationModule.setupRequest(_requestId, _requestData);
  }

  /**
   * @notice Tests that escalateDispute reverts if a dispute is escalated before the bond escalation deadline is over.
   *         Conditions to reach this check:
   *                                         - The _requestId tied to the dispute tied to _disputeId must be valid (non-zero)
   *                                         - The block.timestamp has to be <= bond escalation deadline
   */
  function test_escalateDisputeRevertEscalationDuringBondEscalation(bytes32 _disputeId, bytes32 _requestId) public {
    // Assume _requestId is not zero
    vm.assume(_requestId > 0);

    // Creates a fake dispute and mocks Oracle.getDispute to return it when called.
    _mockDispute(_disputeId, _requestId);

    // Set _bondEscalationDeadline to be the current timestamp to reach the second condition.
    uint256 _bondEscalationDeadline = block.timestamp;

    // Populate the requestData for the given requestId
    _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, tyingBuffer, disputeWindow);

    // Setting this dispute as the one going through the bond escalation process, as the user can only
    // dispute once before the bond escalation deadline is over, and that dispute goes through the escalation module.
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    // Expect Oracle.getDispute to be called.
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));

    // Expect the call to revert with BondEscalationNotOver
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationNotOver.selector);

    // Call disputeEscalated()
    vm.prank(address(oracle));
    bondEscalationModule.disputeEscalated(_disputeId);
  }

  /**
   * @notice Tests that escalateDispute reverts if a dispute that went through the bond escalation mechanism but isn't active
   *         anymore is escalated.
   *         Conditions to reach this check:
   *             - The _requestId tied to the dispute tied to _disputeId must be valid (non-zero)
   *             - The block.timestamp has to be > bond escalation deadline
   *             - The dispute has to have gone through the bond escalation process before
   *             - The status of the bond escalation mechanism has to be different from Active
   */
  function test_escalateDisputeRevertIfEscalatingNonActiveDispute(
    bytes32 _disputeId,
    bytes32 _requestId,
    uint8 _status
  ) public {
    // Assume _requestId is not zero
    vm.assume(_requestId > 0);

    // Assume the status will be any available other but Active
    vm.assume(_status != uint8(IBondEscalationModule.BondEscalationStatus.Active) && _status < 4);

    // Creates a fake dispute and mocks Oracle.getDispute to return it when called.
    _mockDispute(_disputeId, _requestId);

    // Set a tying buffer to show that this can happen even in the tying buffer if the dispute was settled
    uint256 _tyingBuffer = 1000;

    // Make the current timestamp be greater than the bond escalation deadline
    uint256 _bondEscalationDeadline = block.timestamp - 1;

    // Populate the requestData for the given requestId
    _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);

    // Set the bond escalation status of the given requestId to something different than Active
    bondEscalationModule.forTest_setBondEscalationStatus(
      _requestId, IBondEscalationModule.BondEscalationStatus(_status)
    );

    // Set the dispute to be the one that went through the bond escalation process for the given requestId
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    // Expect Oracle.getDispute to be called.
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));

    // Expect the call to revert with NotEscalatable
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_NotEscalatable.selector);

    // Call disputeEscalated()
    vm.prank(address(oracle));
    bondEscalationModule.disputeEscalated(_disputeId);
  }

  /**
   * @notice Tests that escalateDispute reverts if a dispute that went through the bond escalation mechanism and is still active
   *         but its pledges are not tied even after the tying buffer is escalated.
   *         Conditions to reach this check:
   *             - The _requestId tied to the dispute tied to _disputeId must be valid (non-zero)
   *             - The block.timestamp has to be > bond escalation deadline + tying buffer
   *             - The dispute has to have gone or be going through the bond escalation process
   *             - The pledges must not be tied
   */
  function test_escalateDisputeRevertIfEscalatingDisputeIsNotTied(bytes32 _disputeId, bytes32 _requestId) public {
    // Assume _requestId is not zero
    vm.assume(_requestId > 0);

    // Creates a fake dispute and mocks Oracle.getDispute to return it when called.
    _mockDispute(_disputeId, _requestId);

    // Set a tying buffer to make the test more explicit
    uint256 _tyingBuffer = 1000;

    // Set bond escalation deadline to be the current timestamp. We will warp this.
    uint256 _bondEscalationDeadline = block.timestamp;

    // Set the number of pledgers to be different
    uint256 _numForPledgers = 1;
    uint256 _numAgainstPledgers = 2;

    // Warp the current timestamp so we are past the tyingBuffer
    vm.warp(_bondEscalationDeadline + _tyingBuffer + 1);

    // Populate the requestData for the given requestId
    _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);

    // Set the bond escalation status of the given requestId to Active
    bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);

    // Set the dispute to be the one that went through the bond escalation process for the given requestId
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    // Set the number of pledgers for both sides
    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    // Expect Oracle.getDispute to be called.
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));

    // Expect the call to revert with NotEscalatable
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_NotEscalatable.selector);

    // Call disputeEscalated()
    vm.prank(address(oracle));
    bondEscalationModule.disputeEscalated(_disputeId);
  }

  /**
   * @notice Tests that escalateDispute escalates the dispute going through the bond escalation mechanism correctly when the
   *         pledges are tied and the dispute is still active.
   *         Conditions for the function to succeed:
   *             - The _requestId tied to the dispute tied to _disputeId must be valid (non-zero)
   *             - The block.timestamp has to be > bond escalation deadline
   *             - The dispute has to have gone or be going through the bond escalation process
   *             - The pledges must be tied
   */
  function test_escalateDisputeEscalateTiedDispute(bytes32 _disputeId, bytes32 _requestId) public {
    // Assume _requestId is not zero
    vm.assume(_requestId > 0);
    vm.assume(_disputeId > 0);

    // Creates a fake dispute and mocks Oracle.getDispute to return it when called.
    _mockDispute(_disputeId, _requestId);

    // Set a tying buffer
    uint256 _tyingBuffer = 1000;

    // Set bond escalation deadline to be the current timestamp. We will warp this.
    uint256 _bondEscalationDeadline = block.timestamp;

    // Set the number of pledgers to be the same. This means the pledges are tied.
    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = 2;

    // Warp so we are still in the tying buffer period. This is to show a dispute can be escalated during the buffer if the pledges are tied.
    vm.warp(_bondEscalationDeadline + _tyingBuffer);

    // Populate the requestData for the given requestId
    _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);

    // Set the bond escalation status of the given requestId to Active
    bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);

    // Set the dispute to be the one that went through the bond escalation process for the given requestId
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    // Set the number of pledgers for both sides
    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    // Expect Oracle.getDispute to be called.
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));

    // Expect event
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.Escalated);

    // Call disputeEscalated()
    vm.prank(address(oracle));
    bondEscalationModule.disputeEscalated(_disputeId);

    IBondEscalationModule.BondEscalation memory _escalation = bondEscalationModule.getEscalation(_requestId);
    // Expect the bond escalation status to be changed from Active to Escalated
    assertEq(uint256(_escalation.status), uint256(IBondEscalationModule.BondEscalationStatus.Escalated));
  }

  /**
   * @notice Tests that escalateDispute escalates a dispute not going through the bond escalation mechanism correctly after
   *         the bond mechanism deadline has gone by.
   *         Conditions for the function to succeed:
   *             - The _requestId tied to the dispute tied to _disputeId must be valid (non-zero)
   *             - The block.timestamp has to be > bond escalation deadline
   */
  function test_escalateDisputeEscalateNormalDispute(bytes32 _disputeId, bytes32 _requestId) public {
    // Assume _requestId and _disputeId are not zero
    vm.assume(_requestId > 0);
    vm.assume(_disputeId > 0);

    uint256 _tyingBuffer = 1000;

    // Creates a fake dispute and mocks Oracle.getDispute to return it when called.
    _mockDispute(_disputeId, _requestId);

    // Set bond escalation deadline to be the current timestamp. We will warp this.
    uint256 _bondEscalationDeadline = block.timestamp;

    // Warp so we are past the tying buffer period
    vm.warp(_bondEscalationDeadline + 1);

    // Populate the requestData for the given requestId
    _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);

    // Expect Oracle.getDispute to be called.
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));

    // Call disputeEscalated() and expect this does not fail
    vm.prank(address(oracle));
    bondEscalationModule.disputeEscalated(_disputeId);
  }

  ////////////////////////////////////////////////////////////////////
  //                  Tests for disputeResponse
  ////////////////////////////////////////////////////////////////////

  /**
   * @notice Tests that disputeResponse reverts the caller is not the oracle address.
   */
  function test_disputeResponseRevertIfCallerIsNotOracle(
    bytes32 _requestId,
    bytes32 _responseId,
    address _caller
  ) public {
    vm.assume(_caller != address(oracle));
    vm.prank(_caller);
    vm.expectRevert(IModule.Module_OnlyOracle.selector);
    bondEscalationModule.disputeResponse(_requestId, _responseId, disputer, proposer);
  }

  /**
   * @notice Tests that disputeResponse reverts if the challenge period for the response is over.
   */
  function test_disputeResponseRevertIfDisputeWindowIsOver(bytes32 _requestId, bytes32 _responseId) public {
    uint256 _disputeWindow = 1;

    _setRequestData(_requestId, bondSize, maxEscalations, bondEscalationDeadline, tyingBuffer, _disputeWindow);

    _mockResponse(_responseId, _requestId);
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)));

    // Warp to a time after the disputeWindow is over.
    vm.warp(block.timestamp + _disputeWindow + 1);

    vm.prank(address(oracle));
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_DisputeWindowOver.selector);
    bondEscalationModule.disputeResponse(_requestId, _responseId, disputer, proposer);
  }

  /**
   * @notice Tests that disputeResponse succeeds if someone dispute after the bond escalation deadline is over
   */
  function test_disputeResponseSucceedIfDisputeAfterBondingEscalationDeadline(
    bytes32 _requestId,
    bytes32 _responseId
  ) public {
    //  Set deadline to timestamp so we are still in the bond escalation period
    uint256 _bondEscalationDeadline = block.timestamp - 1;

    // Set the request data for the given requestId
    _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, tyingBuffer, disputeWindow);

    _mockResponse(_responseId, _requestId);
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)));

    vm.mockCall(
      address(accounting),
      abi.encodeWithSignature('bond(address,bytes32,address,uint256)', disputer, _requestId, token, bondSize),
      abi.encode(true)
    );

    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationOver.selector);

    vm.prank(address(oracle));
    bondEscalationModule.disputeResponse(_requestId, _responseId, disputer, proposer);
  }

  /**
   * @notice Tests that disputeReponse succeeds in starting the bond escalation mechanism when someone disputes
   *         the first propose before the bond escalation deadline is over.
   */
  function test_disputeResponseFirstDisputeThroughBondMechanism(bytes32 _requestId, bytes32 _responseId) public {
    //  Set deadline to timestamp so we are still in the bond escalation period
    uint256 _bondEscalationDeadline = block.timestamp;

    // Set the request data for the given requestId
    _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, tyingBuffer, disputeWindow);
    _mockResponse(_responseId, _requestId);

    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)));

    vm.mockCall(
      address(accounting),
      abi.encodeWithSignature('bond(address,bytes32,address,uint256)', disputer, _requestId, token, bondSize),
      abi.encode(true)
    );

    bytes32 _expectedDisputeId = keccak256(abi.encodePacked(disputer, _requestId, _responseId));

    vm.prank(address(oracle));
    vm.expectCall(
      address(accounting),
      abi.encodeWithSignature('bond(address,bytes32,address,uint256)', disputer, _requestId, token, bondSize)
    );

    // Expect event
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit BondEscalationStatusUpdated(_requestId, _expectedDisputeId, IBondEscalationModule.BondEscalationStatus.Active);

    bondEscalationModule.disputeResponse(_requestId, _responseId, disputer, proposer);

    // Assert that the bond escalation status is now active
    assertEq(
      uint256(bondEscalationModule.getEscalation(_requestId).status),
      uint256(IBondEscalationModule.BondEscalationStatus.Active)
    );

    // Assert that the dispute was assigned to the bond escalation process
    assertEq(bondEscalationModule.getEscalation(_requestId).disputeId, _expectedDisputeId);
  }

  function test_disputeResponseEmitsEvent(bytes32 _requestId, bytes32 _responseId) public {
    //  Set deadline to timestamp so we are still in the bond escalation period
    uint256 _bondEscalationDeadline = block.timestamp;

    // Set the request data for the given requestId
    _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, tyingBuffer, disputeWindow);
    _mockResponse(_responseId, _requestId);

    vm.mockCall(
      address(accounting),
      abi.encodeWithSignature('bond(address,bytes32,address,uint256)', disputer, _requestId, token, bondSize),
      abi.encode(true)
    );

    vm.prank(address(oracle));

    // Expect event
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit ResponseDisputed(_requestId, _responseId, disputer, proposer);

    bondEscalationModule.disputeResponse(_requestId, _responseId, disputer, proposer);
  }

  ////////////////////////////////////////////////////////////////////
  //                  Tests for onDisputeStatusChange
  ////////////////////////////////////////////////////////////////////

  /**
   * @notice Tests that onDisputeStatusChange reverts
   */
  function test_onDisputeStatusChangeRevertIfCallerIsNotOracle(
    bytes32 _disputeId,
    bytes32 _requestId,
    address _caller,
    uint8 _status
  ) public {
    vm.assume(_caller != address(oracle));
    vm.assume(_status < 4);
    IOracle.DisputeStatus _disputeStatus = IOracle.DisputeStatus(_status);
    IOracle.Dispute memory _dispute = _getRandomDispute(_requestId, _disputeStatus);
    vm.expectRevert(IModule.Module_OnlyOracle.selector);
    vm.prank(_caller);
    bondEscalationModule.onDisputeStatusChange(_disputeId, _dispute);
  }

  /**
   * @notice Tests that onDisputeStatusChange pays the proposer if the disputer lost
   */
  function test_onDisputeStatusChangeCallPayIfNormalDisputeLost(bytes32 _disputeId, bytes32 _requestId) public {
    IOracle.DisputeStatus _status = IOracle.DisputeStatus.Lost;
    IOracle.Dispute memory _dispute = _getRandomDispute(_requestId, _status);

    _setRequestData(_requestId, bondSize, maxEscalations, bondEscalationDeadline, tyingBuffer, disputeWindow);

    vm.mockCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.disputer, _dispute.proposer, token, bondSize)),
      abi.encode(true)
    );
    vm.expectCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.disputer, _dispute.proposer, token, bondSize))
    );

    vm.mockCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_dispute.proposer, _requestId, token, bondSize)),
      abi.encode(true)
    );
    vm.expectCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_dispute.proposer, _requestId, token, bondSize))
    );

    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, _dispute);
  }

  /**
   * @notice Tests that onDisputeStatusChange pays the disputer if the disputer won
   */
  function test_onDisputeStatusChangeCallPayIfNormalDisputeWon(bytes32 _disputeId, bytes32 _requestId) public {
    IOracle.DisputeStatus _status = IOracle.DisputeStatus.Won;
    IOracle.Dispute memory _dispute = _getRandomDispute(_requestId, _status);

    _setRequestData(_requestId, bondSize, maxEscalations, bondEscalationDeadline, tyingBuffer, disputeWindow);

    vm.mockCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.proposer, _dispute.disputer, token, bondSize)),
      abi.encode(true)
    );
    vm.expectCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.proposer, _dispute.disputer, token, bondSize))
    );

    vm.mockCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_dispute.disputer, _requestId, token, bondSize)),
      abi.encode(true)
    );
    vm.expectCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_dispute.disputer, _requestId, token, bondSize))
    );

    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, _dispute);
  }

  function test_onDisputeStatusChangeEmitsEvent(bytes32 _disputeId, bytes32 _requestId) public {
    IOracle.DisputeStatus _status = IOracle.DisputeStatus.Won;
    IOracle.Dispute memory _dispute = _getRandomDispute(_requestId, _status);

    _setRequestData(_requestId, bondSize, maxEscalations, bondEscalationDeadline, tyingBuffer, disputeWindow);

    vm.mockCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.proposer, _dispute.disputer, token, bondSize)),
      abi.encode(true)
    );
    vm.expectCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.proposer, _dispute.disputer, token, bondSize))
    );

    vm.mockCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_dispute.disputer, _requestId, token, bondSize)),
      abi.encode(true)
    );
    vm.expectCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_dispute.disputer, _requestId, token, bondSize))
    );

    // Expect the event
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit DisputeStatusChanged(
      _requestId, _dispute.responseId, _dispute.disputer, _dispute.proposer, IOracle.DisputeStatus.Won
    );

    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, _dispute);
  }

  /**
   * @notice Tests that onDisputeStatusChange returns early if the dispute has gone through the bond
   *         escalation mechanism but no one pledged
   */
  function test_onDisputeStatusChangeEarlyReturnIfBondEscalatedDisputeHashNoPledgers(
    bytes32 _disputeId,
    bytes32 _requestId
  ) public {
    IOracle.DisputeStatus _status = IOracle.DisputeStatus.Won;
    IOracle.Dispute memory _dispute = _getRandomDispute(_requestId, _status);

    _setRequestData(_requestId, bondSize, maxEscalations, bondEscalationDeadline, tyingBuffer, disputeWindow);

    uint256 _numForPledgers = 0;
    uint256 _numAgainstPledgers = 0;

    // Set bond escalation data to have no pledgers
    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    // Set this dispute to have gone through the bond escalation process
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    // Set the bond escalation status to Escalated, which is the only possible one for this function
    bondEscalationModule.forTest_setBondEscalationStatus(
      _requestId, IBondEscalationModule.BondEscalationStatus.Escalated
    );

    vm.mockCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.proposer, _dispute.disputer, token, bondSize)),
      abi.encode(true)
    );
    vm.expectCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.proposer, _dispute.disputer, token, bondSize))
    );

    vm.mockCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_dispute.disputer, _requestId, token, bondSize)),
      abi.encode(true)
    );
    vm.expectCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_dispute.disputer, _requestId, token, bondSize))
    );

    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, _dispute);

    // If it remains at escalated it means it returned early as it didn't update the bond escalation status
    assertEq(
      uint256(bondEscalationModule.getEscalation(_requestId).status),
      uint256(IBondEscalationModule.BondEscalationStatus.Escalated)
    );
  }

  /**
   * @notice Tests that onDisputeStatusChange changes the status of the bond escalation if the
   *         dispute went through the bond escalation process, as well as testing that it calls
   *         payPledgersWon with the correct arguments. In the Won case, this would be, passing
   *         the users that pledged in favor of the dispute, as they have won.
   */
  function test_onDisputeStatusChangeShouldChangeBondEscalationStatusAndCallPayPledgersWon(
    bytes32 _disputeId,
    bytes32 _requestId
  ) public {
    IOracle.DisputeStatus _status = IOracle.DisputeStatus.Won;
    IOracle.Dispute memory _dispute = _getRandomDispute(_requestId, _status);

    uint256 _bondSize = 1000;

    _setRequestData(_requestId, _bondSize, maxEscalations, bondEscalationDeadline, tyingBuffer, disputeWindow);

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = 2;

    // Set bond escalation data to have pledgers and to return the winning for pledgers as in this case they won the escalation
    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    // Set this dispute to have gone through the bond escalation process
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    // Set the bond escalation status to Escalated, which is the only possible one for this function
    bondEscalationModule.forTest_setBondEscalationStatus(
      _requestId, IBondEscalationModule.BondEscalationStatus.Escalated
    );

    vm.mockCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.proposer, _dispute.disputer, token, _bondSize)),
      abi.encode(true)
    );

    vm.mockCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_dispute.disputer, _requestId, token, _bondSize)),
      abi.encode(true)
    );

    vm.mockCall(
      address(accounting),
      abi.encodeCall(
        IBondEscalationAccounting.onSettleBondEscalation,
        (_requestId, _disputeId, true, token, _bondSize << 1, _numForPledgers)
      ),
      abi.encode()
    );

    vm.expectCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.proposer, _dispute.disputer, token, _bondSize))
    );

    vm.expectCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_dispute.disputer, _requestId, token, _bondSize))
    );

    vm.expectCall(
      address(accounting),
      abi.encodeCall(
        IBondEscalationAccounting.onSettleBondEscalation,
        (_requestId, _disputeId, true, token, _bondSize << 1, _numForPledgers)
      )
    );

    // Expect event
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.DisputerWon);

    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, _dispute);

    assertEq(
      uint256(bondEscalationModule.getEscalation(_requestId).status),
      uint256(IBondEscalationModule.BondEscalationStatus.DisputerWon)
    );
  }

  /**
   * @notice Tests that onDisputeStatusChange changes the status of the bond escalation if the
   *         dispute went through the bond escalation process, as well as testing that it calls
   *         payPledgersWon with the correct arguments. In the Lost case, this would be, passing
   *         the users that pledged against the dispute, as those that pledged in favor have lost .
   */
  function test_onDisputeStatusChangeShouldChangeBondEscalationStatusAndCallPayPledgersLost(
    bytes32 _disputeId,
    bytes32 _requestId
  ) public {
    // Set to Lost so the proposer and againstDisputePledgers win
    IOracle.DisputeStatus _status = IOracle.DisputeStatus.Lost;
    IOracle.Dispute memory _dispute = _getRandomDispute(_requestId, _status);

    uint256 _bondSize = 1000;

    _setRequestData(_requestId, _bondSize, maxEscalations, bondEscalationDeadline, tyingBuffer, disputeWindow);

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = 2;

    // Set bond escalation data to have pledgers and to return the winning for pledgers as in this case they won the escalation
    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    // Set this dispute to have gone through the bond escalation process
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    // Set the bond escalation status to Escalated, which is the only possible one for this function
    bondEscalationModule.forTest_setBondEscalationStatus(
      _requestId, IBondEscalationModule.BondEscalationStatus.Escalated
    );

    vm.mockCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.disputer, _dispute.proposer, token, _bondSize)),
      abi.encode(true)
    );

    vm.mockCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_dispute.proposer, _requestId, token, _bondSize)),
      abi.encode(true)
    );

    vm.mockCall(
      address(accounting),
      abi.encodeCall(
        IBondEscalationAccounting.onSettleBondEscalation,
        (_requestId, _disputeId, false, token, _bondSize << 1, _numAgainstPledgers)
      ),
      abi.encode(true)
    );

    vm.expectCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.disputer, _dispute.proposer, token, _bondSize))
    );

    vm.expectCall(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_dispute.proposer, _requestId, token, _bondSize))
    );

    vm.expectCall(
      address(accounting),
      abi.encodeCall(
        IBondEscalationAccounting.onSettleBondEscalation,
        (_requestId, _disputeId, false, token, _bondSize << 1, _numAgainstPledgers)
      )
    );

    // Expect event
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.DisputerLost);

    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, _dispute);

    assertEq(
      uint256(bondEscalationModule.getEscalation(_requestId).status),
      uint256(IBondEscalationModule.BondEscalationStatus.DisputerLost)
    );
  }

  ////////////////////////////////////////////////////////////////////
  //                  Tests for pledgeForDispute
  ////////////////////////////////////////////////////////////////////
  /**
   * @notice Tests that pledgeForDispute reverts if the dispute does not exist.
   */
  function test_pledgeForDisputeRevertIfDisputeIsZero() public {
    bytes32 _disputeId = 0;
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_DisputeDoesNotExist.selector);
    bondEscalationModule.pledgeForDispute(_disputeId);
  }

  /**
   * @notice Tests that pledgeForDispute reverts if the dispute is not going through the bond escalation mechanism.
   */
  function test_pledgeForDisputeRevertIfTheDisputeIsNotGoingThroughTheBondEscalationProcess(
    bytes32 _disputeId,
    bytes32 _requestId
  ) public {
    vm.assume(_disputeId > 0);
    _mockDispute(_disputeId, _requestId);
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_DisputeNotEscalated.selector);
    bondEscalationModule.pledgeForDispute(_disputeId);
  }

  /**
   * @notice Tests that pledgeForDispute reverts if someone tries to pledge after the tying buffer.
   */
  function test_pledgeForDisputeRevertIfTimestampBeyondTyingBuffer(bytes32 _disputeId, bytes32 _requestId) public {
    vm.assume(_disputeId > 0);
    _mockDispute(_disputeId, _requestId);
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _bondSize = 1;
    uint256 _maxNumberOfEscalations = 1;
    uint256 _bondEscalationDeadline = block.timestamp;
    uint256 _tyingBuffer = 1000;

    vm.warp(_bondEscalationDeadline + _tyingBuffer + 1);

    _setRequestData(
      _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
    );
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationOver.selector);
    bondEscalationModule.pledgeForDispute(_disputeId);
  }

  /**
   * @notice Tests that pledgeForDispute reverts if the maximum number of escalations has been reached.
   */
  function test_pledgeForDisputeRevertIfMaxNumberOfEscalationsReached(bytes32 _disputeId, bytes32 _requestId) public {
    vm.assume(_disputeId > 0);
    _mockDispute(_disputeId, _requestId);
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _bondSize = 1;
    uint256 _maxNumberOfEscalations = 2;
    uint256 _bondEscalationDeadline = block.timestamp - 1;
    uint256 _tyingBuffer = 1000;

    _setRequestData(
      _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
    );

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = _numForPledgers;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    vm.expectRevert(IBondEscalationModule.BondEscalationModule_MaxNumberOfEscalationsReached.selector);
    bondEscalationModule.pledgeForDispute(_disputeId);
  }

  /**
   * @notice Tests that pledgeForDispute reverts if someone tries to pledge in favor of the dispute when there are
   *         more pledges in favor of the dispute than against
   */
  function test_pledgeForDisputeRevertIfThereIsMorePledgedForForDisputeThanAgainst(
    bytes32 _disputeId,
    bytes32 _requestId
  ) public {
    vm.assume(_disputeId > 0);
    _mockDispute(_disputeId, _requestId);
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _bondSize = 1;
    uint256 _maxNumberOfEscalations = 3;
    uint256 _bondEscalationDeadline = block.timestamp + 1;

    _setRequestData(_requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, tyingBuffer, disputeWindow);

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = _numForPledgers - 1;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    vm.expectRevert(IBondEscalationModule.BondEscalationModule_CanOnlySurpassByOnePledge.selector);
    bondEscalationModule.pledgeForDispute(_disputeId);
  }

  /**
   * @notice Tests that pledgeForDispute reverts if the timestamp is within the tying buffer and someone attempts
   *         to pledge when the funds are tied--effectively breaking the tie
   */
  function test_pledgeForDisputeRevertIfAttemptToBreakTieDuringTyingBuffer(
    bytes32 _disputeId,
    bytes32 _requestId
  ) public {
    vm.assume(_disputeId > 0);
    _mockDispute(_disputeId, _requestId);
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _bondSize = 1;
    uint256 _maxNumberOfEscalations = 3;
    uint256 _bondEscalationDeadline = block.timestamp - 1;
    uint256 _tyingBuffer = 1000;

    _setRequestData(
      _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
    );

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = _numForPledgers;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    vm.expectRevert(IBondEscalationModule.BondEscalationModule_CanOnlyTieDuringTyingBuffer.selector);
    bondEscalationModule.pledgeForDispute(_disputeId);
  }

  /**
   * @notice Tests that pledgeForDispute is called successfully
   */
  function test_pledgeForDisputeSuccessfulCall(bytes32 _disputeId, bytes32 _requestId) public {
    vm.assume(_disputeId > 0);
    _mockDispute(_disputeId, _requestId);
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _bondSize = 1000;
    uint256 _maxNumberOfEscalations = 3;
    uint256 _bondEscalationDeadline = block.timestamp - 1;
    uint256 _tyingBuffer = 1000;

    _setRequestData(
      _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
    );

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = _numForPledgers + 1;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    vm.mockCall(
      address(accounting),
      abi.encodeCall(IBondEscalationAccounting.pledge, (address(this), _requestId, _disputeId, token, _bondSize)),
      abi.encode(true)
    );
    vm.expectCall(
      address(accounting),
      abi.encodeCall(IBondEscalationAccounting.pledge, (address(this), _requestId, _disputeId, token, _bondSize))
    );

    // Expect event
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit PledgedInFavorOfDisputer(_disputeId, address(this), _bondSize);

    bondEscalationModule.pledgeForDispute(_disputeId);

    bondEscalationModule.forTest_setDisputeToRequest(_disputeId, _requestId);

    uint256 _pledgesForDispute = bondEscalationModule.getEscalation(_requestId).amountOfPledgesForDispute;
    assertEq(_pledgesForDispute, _numForPledgers + 1);

    uint256 _userPledges = bondEscalationModule.pledgesForDispute(_requestId, address(this));
    assertEq(_userPledges, 1);
  }

  ////////////////////////////////////////////////////////////////////
  //                  Tests for pledgeAgainstDispute
  ////////////////////////////////////////////////////////////////////
  // Note: most of these tests will be identical to those of pledgeForDispute - i'm leaving them just so if we change something
  //       in one function, we remember to change it in the other one as well

  /**
   * @notice Tests that pledgeAgainstDispute reverts if the dispute does not exist.
   */
  function test_pledgeAgainstDisputeRevertIfDisputeIsZero() public {
    bytes32 _disputeId = 0;
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_DisputeDoesNotExist.selector);
    bondEscalationModule.pledgeAgainstDispute(_disputeId);
  }

  /**
   * @notice Tests that pledgeAgainstDispute reverts if the dispute is not going through the bond escalation mechanism.
   */
  function test_pledgeAgainstDisputeRevertIfTheDisputeIsNotGoingThroughTheBondEscalationProcess(
    bytes32 _disputeId,
    bytes32 _requestId
  ) public {
    vm.assume(_disputeId > 0);
    _mockDispute(_disputeId, _requestId);
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_DisputeNotEscalated.selector);
    bondEscalationModule.pledgeAgainstDispute(_disputeId);
  }

  /**
   * @notice Tests that pledgeAgainstDispute reverts if someone tries to pledge after the tying buffer.
   */
  function test_pledgeAgainstDisputeRevertIfTimestampBeyondTyingBuffer(bytes32 _disputeId, bytes32 _requestId) public {
    vm.assume(_disputeId > 0);
    _mockDispute(_disputeId, _requestId);
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _bondSize = 1;
    uint256 _maxNumberOfEscalations = 1;
    uint256 _bondEscalationDeadline = block.timestamp;
    uint256 _tyingBuffer = 1000;

    vm.warp(_bondEscalationDeadline + _tyingBuffer + 1);

    _setRequestData(
      _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
    );
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationOver.selector);
    bondEscalationModule.pledgeAgainstDispute(_disputeId);
  }

  /**
   * @notice Tests that pledgeAgainstDispute reverts if the maximum number of escalations has been reached.
   */
  function test_pledgeAgainstDisputeRevertIfMaxNumberOfEscalationsReached(
    bytes32 _disputeId,
    bytes32 _requestId
  ) public {
    vm.assume(_disputeId > 0);
    _mockDispute(_disputeId, _requestId);
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _bondSize = 1;
    uint256 _maxNumberOfEscalations = 2;
    uint256 _bondEscalationDeadline = block.timestamp - 1;
    uint256 _tyingBuffer = 1000;

    _setRequestData(
      _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
    );

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = _numForPledgers;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    vm.expectRevert(IBondEscalationModule.BondEscalationModule_MaxNumberOfEscalationsReached.selector);
    bondEscalationModule.pledgeAgainstDispute(_disputeId);
  }

  /**
   * @notice Tests that pledgeAgainstDispute reverts if someone tries to pledge in favor of the dispute when there are
   *         more pledges against of the dispute than in favor of it
   */
  function test_pledgeAgainstDisputeRevertIfThereIsMorePledgedAgainstDisputeThanFor(
    bytes32 _disputeId,
    bytes32 _requestId
  ) public {
    vm.assume(_disputeId > 0);
    _mockDispute(_disputeId, _requestId);
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _bondSize = 1;
    uint256 _maxNumberOfEscalations = 3;
    uint256 _bondEscalationDeadline = block.timestamp + 1;

    _setRequestData(_requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, tyingBuffer, disputeWindow);

    uint256 _numAgainstPledgers = 2;
    uint256 _numForPledgers = _numAgainstPledgers - 1;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    vm.expectRevert(IBondEscalationModule.BondEscalationModule_CanOnlySurpassByOnePledge.selector);
    bondEscalationModule.pledgeAgainstDispute(_disputeId);
  }

  /**
   * @notice Tests that pledgeAgainstDispute reverts if the timestamp is within the tying buffer and someone attempts
   *         to pledge when the funds are tied--effectively breaking the tie
   */
  function test_pledgeAgainstDisputeRevertIfAttemptToBreakTieDuringTyingBuffer(
    bytes32 _disputeId,
    bytes32 _requestId
  ) public {
    vm.assume(_disputeId > 0);
    _mockDispute(_disputeId, _requestId);
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _bondSize = 1;
    uint256 _maxNumberOfEscalations = 3;
    uint256 _bondEscalationDeadline = block.timestamp - 1;
    uint256 _tyingBuffer = 1000;

    _setRequestData(
      _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
    );

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = _numForPledgers;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    vm.expectRevert(IBondEscalationModule.BondEscalationModule_CanOnlyTieDuringTyingBuffer.selector);
    bondEscalationModule.pledgeAgainstDispute(_disputeId);
  }

  /**
   * @notice Tests that pledgeAgainstDispute is called successfully
   */
  function test_pledgeAgainstDisputeSuccessfulCall(bytes32 _disputeId, bytes32 _requestId) public {
    vm.assume(_disputeId > 0);
    _mockDispute(_disputeId, _requestId);
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _bondSize = 1000;
    uint256 _maxNumberOfEscalations = 3;
    uint256 _bondEscalationDeadline = block.timestamp - 1;
    uint256 _tyingBuffer = 1000;

    _setRequestData(
      _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
    );

    uint256 _numAgainstPledgers = 2;
    uint256 _numForPledgers = _numAgainstPledgers + 1;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    vm.mockCall(
      address(accounting),
      abi.encodeCall(IBondEscalationAccounting.pledge, (address(this), _requestId, _disputeId, token, _bondSize)),
      abi.encode(true)
    );
    vm.expectCall(
      address(accounting),
      abi.encodeCall(IBondEscalationAccounting.pledge, (address(this), _requestId, _disputeId, token, _bondSize))
    );

    // Expect event
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit PledgedInFavorOfProposer(_disputeId, address(this), _bondSize);

    bondEscalationModule.pledgeAgainstDispute(_disputeId);

    bondEscalationModule.forTest_setDisputeToRequest(_disputeId, _requestId);

    uint256 _pledgesForDispute = bondEscalationModule.getEscalation(_requestId).amountOfPledgesAgainstDispute;
    assertEq(_pledgesForDispute, _numAgainstPledgers + 1);

    uint256 _userPledges = bondEscalationModule.pledgesAgainstDispute(_requestId, address(this));
    assertEq(_userPledges, 1);
  }

  ////////////////////////////////////////////////////////////////////
  //                  Tests for settleBondEscalation
  ////////////////////////////////////////////////////////////////////

  /**
   * @notice Tests that settleBondEscalation reverts if someone tries to settle the escalation before the tying buffer
   *         has elapsed.
   */
  function test_settleBondEscalationRevertIfTimestampLessThanEndOfTyingBuffer(bytes32 _requestId) public {
    uint256 _bondEscalationDeadline = block.timestamp;
    _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, tyingBuffer, disputeWindow);
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationNotOver.selector);
    bondEscalationModule.settleBondEscalation(_requestId);
  }

  /**
   * @notice Tests that settleBondEscalation reverts if someone tries to settle a bond-escalated dispute that
   *         is not active.
   */
  function test_settleBondEscalationRevertIfStatusOfBondEscalationIsNotActive(bytes32 _requestId) public {
    uint256 _bondEscalationDeadline = block.timestamp;
    uint256 _tyingBuffer = 1000;

    vm.warp(_bondEscalationDeadline + _tyingBuffer + 1);

    _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);
    bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.None);
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationCantBeSettled.selector);
    bondEscalationModule.settleBondEscalation(_requestId);
  }

  /**
   * @notice Tests that settleBondEscalation reverts if someone tries to settle a bondescalated dispute that
   *         has the same number of pledgers.
   */
  function test_settleBondEscalationRevertIfSameNumberOfPledgers(bytes32 _requestId, bytes32 _disputeId) public {
    uint256 _bondEscalationDeadline = block.timestamp;
    uint256 _tyingBuffer = 1000;

    vm.warp(_bondEscalationDeadline + _tyingBuffer + 1);

    _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);
    bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _numForPledgers = 5;
    uint256 _numAgainstPledgers = _numForPledgers;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    vm.expectRevert(IBondEscalationModule.BondEscalationModule_ShouldBeEscalated.selector);

    bondEscalationModule.settleBondEscalation(_requestId);
  }

  /**
   * @notice Tests that settleBondEscalation is called successfully.
   */
  function test_settleBondEscalationSuccessfulCallDisputerWon(bytes32 _requestId, bytes32 _disputeId) public {
    uint256 _bondSize = 1000;
    uint256 _bondEscalationDeadline = block.timestamp;
    uint256 _tyingBuffer = 1000;

    vm.warp(_bondEscalationDeadline + _tyingBuffer + 1);

    _setRequestData(_requestId, _bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);
    bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = _numForPledgers - 1;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    uint256 _amountToPay = _bondSize + (_numAgainstPledgers * _bondSize) / _numForPledgers;

    vm.mockCall(
      address(accounting),
      abi.encodeCall(
        IBondEscalationAccounting.onSettleBondEscalation,
        (_requestId, _disputeId, true, token, _amountToPay, _numForPledgers)
      ),
      abi.encode(true)
    );
    vm.expectCall(
      address(accounting),
      abi.encodeCall(
        IBondEscalationAccounting.onSettleBondEscalation,
        (_requestId, _disputeId, true, token, _amountToPay, _numForPledgers)
      )
    );

    // Expect event
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.DisputerWon);

    bondEscalationModule.settleBondEscalation(_requestId);
    assertEq(
      uint256(bondEscalationModule.getEscalation(_requestId).status),
      uint256(IBondEscalationModule.BondEscalationStatus.DisputerWon)
    );
  }

  /**
   * @notice Tests that settleBondEscalation is called successfully.
   */
  function test_settleBondEscalationSuccessfulCallDisputerLost(bytes32 _requestId, bytes32 _disputeId) public {
    uint256 _bondSize = 1000;
    uint256 _bondEscalationDeadline = block.timestamp;
    uint256 _tyingBuffer = 1000;

    vm.warp(_bondEscalationDeadline + _tyingBuffer + 1);

    _setRequestData(_requestId, _bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);
    bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _numAgainstPledgers = 2;
    uint256 _numForPledgers = _numAgainstPledgers - 1;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    uint256 _amountToPay = _bondSize + (_numForPledgers * _bondSize) / _numAgainstPledgers;

    vm.mockCall(
      address(accounting),
      abi.encodeCall(
        IBondEscalationAccounting.onSettleBondEscalation,
        (_requestId, _disputeId, false, token, _amountToPay, _numAgainstPledgers)
      ),
      abi.encode()
    );
    vm.expectCall(
      address(accounting),
      abi.encodeCall(
        IBondEscalationAccounting.onSettleBondEscalation,
        (_requestId, _disputeId, false, token, _amountToPay, _numAgainstPledgers)
      )
    );

    // Expect event
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.DisputerLost);

    bondEscalationModule.settleBondEscalation(_requestId);
    assertEq(
      uint256(bondEscalationModule.getEscalation(_requestId).status),
      uint256(IBondEscalationModule.BondEscalationStatus.DisputerLost)
    );
  }

  ////////////////////////////////////////////////////////////////////
  //                  Tests for decodeRequestData
  ////////////////////////////////////////////////////////////////////
  /**
   * @notice Tests that decodeRequestData decodes the data correctly
   */
  function test_decodeRequestDataReturnTheCorrectData(
    bytes32 _requestId,
    uint256 _bondSize,
    uint256 _maxNumberOfEscalations,
    uint256 _bondEscalationDeadline,
    uint256 _tyingBuffer,
    uint256 _disputeWindow
  ) public {
    _setRequestData(
      _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, _disputeWindow
    );
    IBondEscalationModule.RequestParameters memory _params = bondEscalationModule.decodeRequestData(_requestId);
    assertEq(address(accounting), address(_params.accountingExtension));
    assertEq(address(token), address(_params.bondToken));
    assertEq(_bondSize, _params.bondSize);
    assertEq(_maxNumberOfEscalations, _params.maxNumberOfEscalations);
    assertEq(_bondEscalationDeadline, _params.bondEscalationDeadline);
    assertEq(_tyingBuffer, _params.tyingBuffer);
    assertEq(_disputeWindow, _params.disputeWindow);
  }

  ////////////////////////////////////////////////////////////////////
  //                     Helper functions
  ////////////////////////////////////////////////////////////////////

  function _setRequestData(
    bytes32 _requestId,
    uint256 _bondSize,
    uint256 _maxNumberOfEscalations,
    uint256 _bondEscalationDeadline,
    uint256 _tyingBuffer,
    uint256 _disputeWindow
  ) internal {
    bytes memory _data = abi.encode(
      IBondEscalationModule.RequestParameters({
        accountingExtension: accounting,
        bondToken: token,
        bondSize: _bondSize,
        maxNumberOfEscalations: _maxNumberOfEscalations,
        bondEscalationDeadline: _bondEscalationDeadline,
        tyingBuffer: _tyingBuffer,
        disputeWindow: _disputeWindow
      })
    );
    bondEscalationModule.forTest_setRequestData(_requestId, _data);
  }

  function _mockDispute(bytes32 _disputeId, bytes32 _requestId) internal {
    IOracle.Dispute memory _dispute = IOracle.Dispute({
      disputer: disputer,
      responseId: bytes32('response'),
      proposer: proposer,
      requestId: _requestId,
      status: IOracle.DisputeStatus.Active,
      createdAt: block.timestamp
    });

    vm.mockCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_dispute));
  }

  function _mockResponse(bytes32 _responseId, bytes32 _requestId) internal {
    IOracle.Response memory _response = IOracle.Response({
      createdAt: block.timestamp,
      proposer: proposer,
      requestId: _requestId,
      disputeId: 0,
      response: abi.encode(bytes32('response'))
    });

    vm.mockCall(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)), abi.encode(_response));
  }

  function _getRandomDispute(
    bytes32 _requestId,
    IOracle.DisputeStatus _status
  ) internal view returns (IOracle.Dispute memory _dispute) {
    _dispute = IOracle.Dispute({
      disputer: disputer,
      responseId: bytes32('response'),
      proposer: proposer,
      requestId: _requestId,
      status: _status,
      createdAt: block.timestamp
    });
  }

  function _setBondEscalation(
    bytes32 _requestId,
    uint256 _numForPledgers,
    uint256 _numAgainstPledgers
  ) internal returns (address[] memory _forPledgers, address[] memory _againstPledgers) {
    _forPledgers = new address[](_numForPledgers);
    _againstPledgers = new address[](_numAgainstPledgers);
    address _forPledger;
    address _againstPledger;

    for (uint256 _i; _i < _numForPledgers; _i++) {
      _forPledger = makeAddr(string.concat('forPledger', Strings.toString(_i)));
      _forPledgers[_i] = _forPledger;
    }

    for (uint256 _j; _j < _numAgainstPledgers; _j++) {
      _againstPledger = makeAddr(string.concat('againstPledger', Strings.toString(_j)));
      _againstPledgers[_j] = _againstPledger;
    }

    // IBondEscalationModule.BondEscalation memory _escalation = bondEscalationModule.getEscalation(_requestId);

    bondEscalationModule.forTest_setBondEscalation(_requestId, _forPledgers, _againstPledgers);

    return (_forPledgers, _againstPledgers);
  }
}
