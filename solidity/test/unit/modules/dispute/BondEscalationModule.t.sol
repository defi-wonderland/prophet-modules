// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IModule} from '@defi-wonderland/prophet-core/solidity/interfaces/IModule.sol';
import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';
import {ValidatorLib} from '@defi-wonderland/prophet-core/solidity/libraries/ValidatorLib.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';

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
}

/**
 * @title Bonded Response Module Unit tests
 */
contract BaseTest is Test, Helpers {
  // The target contract
  ForTest_BondEscalationModule public bondEscalationModule;
  // A mock oracle
  IOracle public oracle;
  // A mock accounting extension
  IBondEscalationAccounting public accounting;
  // A mock token
  IERC20 public token;
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
  event PledgedForDispute(bytes32 indexed _disputeId, address indexed _pledger, uint256 indexed _amount);
  event PledgedAgainstDispute(bytes32 indexed _disputeId, address indexed _pledger, uint256 indexed _amount);
  event BondEscalationStatusUpdated(
    bytes32 indexed _requestId, bytes32 indexed _disputeId, IBondEscalationModule.BondEscalationStatus _status
  );
  event ResponseDisputed(
    bytes32 indexed _requestId,
    bytes32 indexed _responseId,
    bytes32 indexed _disputeId,
    IOracle.Dispute _dispute,
    uint256 _blockNumber
  );
  event DisputeStatusChanged(bytes32 indexed _disputeId, IOracle.Dispute _dispute, IOracle.DisputeStatus _status);

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

    // Set to an arbitrary large value to avoid unintended reverts
    disputeWindow = type(uint128).max;

    // Avoid starting at 0 for time sensitive tests
    vm.warp(123_456);

    mockDispute = IOracle.Dispute({
      disputer: disputer,
      responseId: bytes32('response'),
      proposer: proposer,
      requestId: bytes32('69')
    });

    mockResponse =
      IOracle.Response({proposer: proposer, requestId: bytes32('69'), response: abi.encode(bytes32('response'))});

    bondEscalationModule = new ForTest_BondEscalationModule(oracle);
  }

  function _getRandomDispute(bytes32 _requestId) internal view returns (IOracle.Dispute memory _dispute) {
    _dispute =
      IOracle.Dispute({disputer: disputer, responseId: bytes32('response'), proposer: proposer, requestId: _requestId});
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

    bondEscalationModule.forTest_setBondEscalation(_requestId, _forPledgers, _againstPledgers);

    return (_forPledgers, _againstPledgers);
  }
}

contract BondEscalationModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleName() public view {
    assertEq(bondEscalationModule.moduleName(), 'BondEscalationModule');
  }

  /**
   * @notice Tests that decodeRequestData decodes the data correctly
   */
  function test_decodeRequestDataReturnTheCorrectData(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    mockRequest.disputeModuleData = abi.encode(_params);

    IBondEscalationModule.RequestParameters memory _decodedParams =
      bondEscalationModule.decodeRequestData(mockRequest.disputeModuleData);

    // Check: does the stored data match the provided one?
    assertEq(address(_params.accountingExtension), address(_decodedParams.accountingExtension));
    assertEq(address(_params.bondToken), address(_decodedParams.bondToken));
    assertEq(_params.bondSize, _decodedParams.bondSize);
    assertEq(_params.maxNumberOfEscalations, _decodedParams.maxNumberOfEscalations);
    assertEq(_params.bondEscalationDeadline, _decodedParams.bondEscalationDeadline);
    assertEq(_params.tyingBuffer, _decodedParams.tyingBuffer);
    assertEq(_params.disputeWindow, _decodedParams.disputeWindow);
  }

  /**
   * @notice Test that the validateParameters function correctly checks the parameters
   */
  function test_validateParameters(IBondEscalationModule.RequestParameters calldata _params) public view {
    if (
      address(_params.accountingExtension) == address(0) || address(_params.bondToken) == address(0)
        || _params.bondSize == 0 || _params.bondEscalationDeadline == 0 || _params.maxNumberOfEscalations == 0
        || _params.tyingBuffer == 0 || _params.disputeWindow == 0
    ) {
      assertFalse(bondEscalationModule.validateParameters(abi.encode(_params)));
    } else {
      assertTrue(bondEscalationModule.validateParameters(abi.encode(_params)));
    }
  }
}

contract BondEscalationModule_Unit_EscalateDispute is BaseTest {
  /**
   * @notice Tests that escalateDispute reverts if a dispute is escalated before the bond escalation deadline is over.
   *         Conditions to reach this check:
   *                                         - The _requestId tied to the dispute tied to _disputeId must be valid (non-zero)
   *                                         - The block.timestamp has to be <= bond escalation deadline
   */
  function test_revertEscalationDuringBondEscalation(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    // Set _bondEscalationDeadline to be the current timestamp to reach the second condition.
    _params.bondEscalationDeadline = block.timestamp;

    mockRequest.disputeModuleData = abi.encode(_params);
    bytes32 _requestId = _getId(mockRequest);

    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    // Setting this dispute as the one going through the bond escalation process, as the user can only
    // dispute once before the bond escalation deadline is over, and that dispute goes through the escalation module.
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    // Check: does it revert if the bond escalation is not over yet?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationNotOver.selector);
    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, mockRequest, mockResponse, mockDispute);
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
  function test_revertIfEscalatingNonActiveDispute(
    uint8 _status,
    IBondEscalationModule.RequestParameters memory _params
  ) public assumeFuzzable(address(_params.accountingExtension)) {
    // Assume the status will be any available other but Active
    vm.assume(_status != uint8(IBondEscalationModule.BondEscalationStatus.Active) && _status < 4);

    _params.accountingExtension = IBondEscalationAccounting(makeAddr('BondEscalationAccounting'));
    // Set a tying buffer to show that this can happen even in the tying buffer if the dispute was settled
    _params.tyingBuffer = 1000;
    // Make the current timestamp be greater than the bond escalation deadline
    _params.bondEscalationDeadline = block.timestamp - 1;

    mockRequest.disputeModuleData = abi.encode(_params);
    bytes32 _requestId = _getId(mockRequest);

    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Set the bond escalation status of the given requestId to something different than Active
    bondEscalationModule.forTest_setBondEscalationStatus(
      _requestId, IBondEscalationModule.BondEscalationStatus(_status)
    );

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    // Set the dispute to be the one that went through the bond escalation process for the given requestId
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    // Check: does it revert if the dispute is not escalatable?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_NotEscalatable.selector);
    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, mockRequest, mockResponse, mockDispute);
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
  function test_revertIfEscalatingDisputeIsNotTied(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    // Set a tying buffer to make the test more explicit
    _params.tyingBuffer = 1000;
    // Set bond escalation deadline to be the current timestamp. We will warp this.
    _params.bondEscalationDeadline = block.timestamp;

    mockRequest.disputeModuleData = abi.encode(_params);
    bytes32 _requestId = _getId(mockRequest);

    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Set the number of pledgers to be different
    uint256 _numForPledgers = 1;
    uint256 _numAgainstPledgers = 2;

    // Warp the current timestamp so we are past the tyingBuffer
    vm.warp(_params.bondEscalationDeadline + _params.tyingBuffer + 1);

    // Set the bond escalation status of the given requestId to Active
    bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);

    // Set the dispute to be the one that went through the bond escalation process for the given requestId
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    // Set the number of pledgers for both sides
    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    // Check: does it revert if the dispute is not escalatable?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_NotEscalatable.selector);
    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, mockRequest, mockResponse, mockDispute);
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
  function test_escalateTiedDispute(
    address _proposer,
    address _disputer,
    IBondEscalationModule.RequestParameters memory _params
  ) public assumeFuzzable(address(_params.accountingExtension)) {
    // Set bond escalation deadline to be the current timestamp. We will warp this.
    _params.bondEscalationDeadline = block.timestamp;
    // Set a tying buffer
    _params.tyingBuffer = 1000;
    _params.accountingExtension = IBondEscalationAccounting(makeAddr('BondEscalationAccounting'));

    mockRequest.disputeModuleData = abi.encode(_params);
    bytes32 _requestId = _getId(mockRequest);

    mockResponse.requestId = _requestId;
    mockResponse.proposer = _proposer;
    bytes32 _responseId = _getId(mockResponse);

    mockDispute.requestId = _requestId;
    mockDispute.responseId = _responseId;
    mockDispute.proposer = _proposer;
    mockDispute.disputer = _disputer;
    bytes32 _disputeId = _getId(mockDispute);

    // Set the number of pledgers to be the same. This means the pledges are tied.
    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = 2;

    // Warp so we are still in the tying buffer period. This is to show a dispute can be escalated during the buffer if the pledges are tied.
    vm.warp(_params.bondEscalationDeadline + _params.tyingBuffer);

    // Set the bond escalation status of the given requestId to Active
    bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);

    // Set the dispute to be the one that went through the bond escalation process for the given requestId
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    // Set the number of pledgers for both sides
    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.Escalated);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, mockRequest, mockResponse, mockDispute);

    IBondEscalationModule.BondEscalation memory _escalation = bondEscalationModule.getEscalation(_requestId);
    // Check: is the bond escalation status properly updated?
    assertEq(uint256(_escalation.status), uint256(IBondEscalationModule.BondEscalationStatus.Escalated));
  }
}

contract BondEscalationModule_Unit_DisputeResponse is BaseTest {
  /**
   * @notice Tests that disputeResponse reverts the caller is not the oracle address.
   */
  function test_revertIfCallerIsNotOracle(address _caller, IOracle.Request calldata _request) public {
    vm.assume(_caller != address(oracle));

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);
    vm.prank(_caller);
    bondEscalationModule.disputeResponse(_request, mockResponse, mockDispute);
  }

  /**
   * @notice Tests that disputeResponse reverts if the challenge period for the response is over.
   */
  function test_revertIfDisputeWindowIsOver(
    uint128 _disputeWindow,
    IBondEscalationModule.RequestParameters memory _params
  ) public assumeFuzzable(address(_params.accountingExtension)) {
    // Set mock request data
    _params.disputeWindow = _disputeWindow;
    mockRequest.disputeModuleData = abi.encode(_params);

    // Compute proper IDs
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;

    bytes32 _responseId = _getId(mockResponse);
    mockDispute.requestId = _requestId;
    mockDispute.responseId = _responseId;

    // Warp to a time after the disputeWindow is over.
    vm.warp(block.timestamp + _disputeWindow + 1);

    // Mock and expect IOracle.responseCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.responseCreatedAt, (_responseId)), abi.encode(1));

    // Check: does it revert if the dispute window is over?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_DisputeWindowOver.selector);
    vm.prank(address(oracle));
    bondEscalationModule.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Tests that disputeResponse succeeds if someone dispute after the bond escalation deadline is over
   */
  function test_succeedIfDisputeAfterBondingEscalationDeadline(
    uint256 _timestamp,
    IBondEscalationModule.RequestParameters memory _params
  ) public assumeFuzzable(address(_params.accountingExtension)) {
    _timestamp = bound(_timestamp, 1, 365 days);
    //  Set deadline to timestamp so we are still in the bond escalation period
    _params.bondEscalationDeadline = _timestamp - 1;
    _params.disputeWindow = _timestamp + 1;
    mockRequest.disputeModuleData = abi.encode(_params);

    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;

    bytes32 _responseId = _getId(mockResponse);
    mockDispute.responseId = _responseId;
    mockDispute.requestId = _requestId;

    // Mock and expect IOracle.responseCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.responseCreatedAt, (_responseId)), abi.encode(1));

    // Mock and expect the accounting extension to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeWithSignature(
        'bond(address,bytes32,address,uint256)', mockDispute.disputer, _requestId, _params.bondToken, _params.bondSize
      ),
      abi.encode(true)
    );

    vm.warp(_timestamp);

    // Check: does it revert if the bond escalation is over?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationOver.selector);
    vm.prank(address(oracle));
    bondEscalationModule.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Tests that disputeResponse succeeds in starting the bond escalation mechanism when someone disputes
   *         the first propose before the bond escalation deadline is over.
   */
  function test_firstDisputeThroughBondMechanism(
    address _disputer,
    IBondEscalationModule.RequestParameters memory _params
  ) public assumeFuzzable(address(_params.accountingExtension)) {
    //  Set deadline to timestamp so we are still in the bond escalation period
    _params.disputeWindow = block.timestamp;
    _params.bondEscalationDeadline = block.timestamp;

    // Compute proper IDs
    mockRequest.disputeModuleData = abi.encode(_params);
    bytes32 _requestId = _getId(mockRequest);

    mockResponse.requestId = _requestId;
    bytes32 _responseId = _getId(mockResponse);

    mockDispute.disputer = _disputer;
    mockDispute.responseId = _responseId;
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect the accounting extension to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeWithSignature(
        'bond(address,bytes32,address,uint256)', _disputer, _requestId, _params.bondToken, _params.bondSize
      ),
      abi.encode(true)
    );

    // Mock and expect IOracle.responseCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.responseCreatedAt, (_responseId)), abi.encode(1));

    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit ResponseDisputed({
      _requestId: _requestId,
      _responseId: _responseId,
      _disputeId: _disputeId,
      _dispute: mockDispute,
      _blockNumber: block.number
    });

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.Active);

    vm.prank(address(oracle));
    bondEscalationModule.disputeResponse(mockRequest, mockResponse, mockDispute);

    // Check: is the bond escalation status now active?
    assertEq(
      uint256(bondEscalationModule.getEscalation(_requestId).status),
      uint256(IBondEscalationModule.BondEscalationStatus.Active)
    );

    // Check: is the dispute assigned to the bond escalation process?
    assertEq(bondEscalationModule.getEscalation(_requestId).disputeId, _disputeId);
  }

  function test_emitsEvent(
    address _disputer,
    address _proposer,
    IBondEscalationModule.RequestParameters memory _params
  ) public assumeFuzzable(address(_params.accountingExtension)) {
    _params.disputeWindow = block.timestamp;
    _params.bondEscalationDeadline = block.timestamp;

    // Compute proper IDs
    mockRequest.disputeModuleData = abi.encode(_params);
    bytes32 _requestId = _getId(mockRequest);

    mockResponse.requestId = _requestId;
    mockResponse.proposer = _proposer;
    bytes32 _responseId = _getId(mockResponse);

    mockDispute.disputer = _disputer;
    mockDispute.requestId = _requestId;
    mockDispute.responseId = _responseId;
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect IOracle.responseCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.responseCreatedAt, (_responseId)), abi.encode(1));

    // Mock and expect the accounting extension to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeWithSignature(
        'bond(address,bytes32,address,uint256)', _disputer, _requestId, _params.bondToken, _params.bondSize
      ),
      abi.encode(true)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit ResponseDisputed(_requestId, _responseId, _disputeId, mockDispute, block.number);

    vm.prank(address(oracle));
    bondEscalationModule.disputeResponse(mockRequest, mockResponse, mockDispute);
  }
}

contract BondEscalationModule_Unit_OnDisputeStatusChange is BaseTest {
  /**
   * @notice Tests that onDisputeStatusChange reverts
   */
  function test_revertIfCallerIsNotOracle(
    bytes32 _disputeId,
    address _caller,
    uint8 _status,
    IOracle.Request calldata _request
  ) public {
    vm.assume(_caller != address(oracle));
    vm.assume(_status < 4);

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);
    vm.prank(_caller);
    bondEscalationModule.onDisputeStatusChange(_disputeId, _request, mockResponse, mockDispute);
  }

  /**
   * @notice Tests that onDisputeStatusChange pays the proposer if the disputer lost
   */
  function test_callPayIfNormalDisputeLost(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    _params.accountingExtension = IBondEscalationAccounting(makeAddr('BondEscalationAccounting'));
    mockRequest.disputeModuleData = abi.encode(_params);
    bytes32 _requestId = _getId(mockRequest);

    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect IAccountingExtension.pay to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IAccountingExtension.pay,
        (_requestId, mockDispute.disputer, mockDispute.proposer, _params.bondToken, _params.bondSize)
      ),
      abi.encode(true)
    );

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Lost)
    );

    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Tests that onDisputeStatusChange pays the disputer if the disputer won
   */
  function test_callPayIfNormalDisputeWon(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    _params.accountingExtension = IBondEscalationAccounting(makeAddr('BondEscalationAccounting'));
    mockRequest.disputeModuleData = abi.encode(_params);
    bytes32 _requestId = _getId(mockRequest);

    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect IAccountingExtension.pay to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IAccountingExtension.pay,
        (_requestId, mockDispute.proposer, mockDispute.disputer, _params.bondToken, _params.bondSize)
      ),
      abi.encode(true)
    );

    // Mock and expect IAccountingExtension.pay to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IAccountingExtension.release, (mockDispute.disputer, _requestId, _params.bondToken, _params.bondSize)
      ),
      abi.encode(true)
    );

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Won)
    );

    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, mockRequest, mockResponse, mockDispute);
  }

  function test_emitsEvent(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    IOracle.DisputeStatus _status = IOracle.DisputeStatus.Won;

    mockRequest.disputeModuleData = abi.encode(_params);
    bytes32 _requestId = _getId(mockRequest);

    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(_status));

    // Mock and expect IAccountingExtension.pay to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IAccountingExtension.pay,
        (_requestId, mockDispute.proposer, mockDispute.disputer, _params.bondToken, _params.bondSize)
      ),
      abi.encode(true)
    );

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IAccountingExtension.release, (mockDispute.disputer, _requestId, _params.bondToken, _params.bondSize)
      ),
      abi.encode(true)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit DisputeStatusChanged(_disputeId, mockDispute, IOracle.DisputeStatus.Won);

    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Tests that onDisputeStatusChange returns early if the dispute has gone through the bond
   *         escalation mechanism but no one pledged
   */
  function test_earlyReturnIfBondEscalatedDisputeHashNoPledgers(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    mockRequest.disputeModuleData = abi.encode(_params);
    bytes32 _requestId = _getId(mockRequest);

    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    uint256 _numForPledgers = 0;
    uint256 _numAgainstPledgers = 0;

    // Set bond escalation data to have no pledgers
    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    // Set this dispute to have gone through the bond escalation process
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    // Set the bond escalation status to Active, which is the only possible one for this function
    bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Won)
    );

    // Mock and expect IAccountingExtension.pay to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IAccountingExtension.pay,
        (_requestId, mockDispute.proposer, mockDispute.disputer, _params.bondToken, _params.bondSize)
      ),
      abi.encode(true)
    );

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IAccountingExtension.release, (mockDispute.disputer, _requestId, _params.bondToken, _params.bondSize)
      ),
      abi.encode(true)
    );

    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, mockRequest, mockResponse, mockDispute);

    // Check: is the bond escalation status properly updated?
    assertEq(
      uint256(bondEscalationModule.getEscalation(_requestId).status),
      uint256(IBondEscalationModule.BondEscalationStatus.DisputerWon)
    );
  }

  /**
   * @notice Tests that onDisputeStatusChange changes the status of the bond escalation if the
   *         dispute went through the bond escalation process, as well as testing that it calls
   *         payPledgersWon with the correct arguments. In the Won case, this would be, passing
   *         the users that pledged in favor of the dispute, as they have won.
   */
  function test_shouldChangeBondEscalationStatusAndCallPayPledgersWon(
    IBondEscalationModule.RequestParameters memory _params,
    uint256 _numPledgers
  ) public assumeFuzzable(address(_params.accountingExtension)) {
    vm.assume(_params.bondSize < type(uint128).max / 2);
    vm.assume(_numPledgers > 0 && _numPledgers < 30);

    IOracle.DisputeStatus _status = IOracle.DisputeStatus.Won;

    mockRequest.disputeModuleData = abi.encode(_params);
    bytes32 _requestId = _getId(mockRequest);

    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Set bond escalation data to have pledgers and to return the winning for pledgers as in this case they won the escalation
    _setBondEscalation(_requestId, _numPledgers, _numPledgers);

    // Set this dispute to have gone through the bond escalation process
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    // Set the bond escalation status to Escalated, which is the only possible one for this function
    bondEscalationModule.forTest_setBondEscalationStatus(
      _requestId, IBondEscalationModule.BondEscalationStatus.Escalated
    );

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(_status));

    // Mock and expect IAccountingExtension.pay to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IAccountingExtension.pay,
        (_requestId, mockDispute.proposer, mockDispute.disputer, _params.bondToken, _params.bondSize)
      ),
      abi.encode(true)
    );

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IAccountingExtension.release, (mockDispute.disputer, _requestId, _params.bondToken, _params.bondSize)
      ),
      abi.encode(true)
    );

    // Mock and expect IBondEscalationAccounting.onSettleBondEscalation to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IBondEscalationAccounting.onSettleBondEscalation,
        (mockRequest, mockDispute, _params.bondToken, _params.bondSize << 1, _numPledgers)
      ),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.DisputerWon);

    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, mockRequest, mockResponse, mockDispute);

    // Check: is the bond escalation status properly updated?
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
  function test_shouldChangeBondEscalationStatusAndCallPayPledgersLost(
    IBondEscalationModule.RequestParameters memory _params,
    uint256 _numPledgers
  ) public assumeFuzzable(address(_params.accountingExtension)) {
    vm.assume(_params.bondSize < type(uint128).max / 2);
    vm.assume(_numPledgers > 0 && _numPledgers < 30);

    // Set to Lost so the proposer and againstDisputePledgers win
    IOracle.DisputeStatus _status = IOracle.DisputeStatus.Lost;

    mockRequest.disputeModuleData = abi.encode(_params);
    bytes32 _requestId = _getId(mockRequest);

    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Set bond escalation data to have pledgers and to return the winning for pledgers as in this case they won the escalation
    _setBondEscalation(_requestId, _numPledgers, _numPledgers);

    // Set this dispute to have gone through the bond escalation process
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    // Set the bond escalation status to Escalated, which is the only possible one for this function
    bondEscalationModule.forTest_setBondEscalationStatus(
      _requestId, IBondEscalationModule.BondEscalationStatus.Escalated
    );

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(_status));

    // Mock and expect IAccountingExtension.pay to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IAccountingExtension.pay,
        (_requestId, mockDispute.disputer, mockDispute.proposer, _params.bondToken, _params.bondSize)
      ),
      abi.encode(true)
    );

    // Mock and expect IBondEscalationAccounting.onSettleBondEscalation to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IBondEscalationAccounting.onSettleBondEscalation,
        (mockRequest, mockDispute, _params.bondToken, _params.bondSize << 1, _numPledgers)
      ),
      abi.encode()
    );

    // Check: is th event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.DisputerLost);

    vm.prank(address(oracle));
    bondEscalationModule.onDisputeStatusChange(_disputeId, mockRequest, mockResponse, mockDispute);

    // Check: is the bond escalation status properly updated?
    assertEq(
      uint256(bondEscalationModule.getEscalation(_requestId).status),
      uint256(IBondEscalationModule.BondEscalationStatus.DisputerLost)
    );
  }
}

contract BondEscalationModule_Unit_PledgeForDispute is BaseTest {
  /**
   * @notice Tests that pledgeForDispute reverts if the dispute body is invalid.
   */
  function test_revertIfInvalidDisputeBody() public {
    // Check: does it revert if the dispute body is invalid?
    vm.expectRevert(ValidatorLib.ValidatorLib_InvalidDisputeBody.selector);
    bondEscalationModule.pledgeForDispute(mockRequest, mockDispute);
  }

  /**
   * @notice Tests that pledgeForDispute reverts if the dispute is not going through the bond escalation mechanism.
   */
  function test_revertIfTheDisputeIsNotGoingThroughTheBondEscalationProcess() public {
    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);

    // Check: does it revert if the dispute is not escalated yet?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_InvalidDispute.selector);
    bondEscalationModule.pledgeForDispute(mockRequest, _dispute);
  }

  /**
   * @notice Tests that pledgeForDispute reverts if someone tries to pledge after the tying buffer.
   */
  function test_revertIfTimestampBeyondTyingBuffer(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    _params.bondSize = 1;
    _params.maxNumberOfEscalations = 1;
    _params.bondEscalationDeadline = block.timestamp;
    _params.tyingBuffer = 1000;
    mockRequest.disputeModuleData = abi.encode(_params);

    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    vm.warp(_params.bondEscalationDeadline + _params.tyingBuffer + 1);

    // Check: does it revert if the bond escalation is over?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationOver.selector);
    bondEscalationModule.pledgeForDispute(mockRequest, _dispute);
  }

  /**
   * @notice Tests that pledgeForDispute reverts if the maximum number of escalations has been reached.
   */
  function test_revertIfMaxNumberOfEscalationsReached(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    _params.bondSize = 1;
    _params.maxNumberOfEscalations = 2;
    _params.bondEscalationDeadline = block.timestamp - 1;
    _params.tyingBuffer = 1000;
    mockRequest.disputeModuleData = abi.encode(_params);

    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = _numForPledgers;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    // Check: does it revert if the maximum number of escalations is reached?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_MaxNumberOfEscalationsReached.selector);
    bondEscalationModule.pledgeForDispute(mockRequest, _dispute);
  }

  /**
   * @notice Tests that pledgeForDispute reverts if someone tries to pledge in favor of the dispute when there are
   *         more pledges in favor of the dispute than against
   */
  function test_revertIfThereIsMorePledgedForForDisputeThanAgainst(
    IBondEscalationModule.RequestParameters memory _params
  ) public assumeFuzzable(address(_params.accountingExtension)) {
    _params.tyingBuffer = bound(_params.tyingBuffer, 0, type(uint128).max);
    _params.bondSize = 1;
    _params.maxNumberOfEscalations = 3;
    _params.bondEscalationDeadline = block.timestamp + 1;
    mockRequest.disputeModuleData = abi.encode(_params);

    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = _numForPledgers - 1;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    // Check: does it revert if trying to pledge in a dispute that is already surpassed?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_CanOnlySurpassByOnePledge.selector);
    bondEscalationModule.pledgeForDispute(mockRequest, _dispute);
  }

  /**
   * @notice Tests that pledgeForDispute reverts if the timestamp is within the tying buffer and someone attempts
   *         to pledge when the funds are tied, effectively breaking the tie
   */
  function test_revertIfAttemptToBreakTieDuringTyingBuffer(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    _params.bondSize = 1;
    _params.maxNumberOfEscalations = 3;
    _params.bondEscalationDeadline = block.timestamp - 1;
    _params.tyingBuffer = 1000;
    mockRequest.disputeModuleData = abi.encode(_params);

    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = _numForPledgers;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    // Check: does it revert if trying to tie outside of the tying buffer?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_CannotBreakTieDuringTyingBuffer.selector);
    bondEscalationModule.pledgeForDispute(mockRequest, _dispute);
  }

  /**
   * @notice Tests that pledgeForDispute is called successfully
   */
  function test_successfulCall(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    _params.bondSize = 1000;
    _params.maxNumberOfEscalations = 3;
    _params.bondEscalationDeadline = block.timestamp - 1;
    _params.tyingBuffer = 1000;
    mockRequest.disputeModuleData = abi.encode(_params);

    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = _numForPledgers + 1;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    // Mock and expect IBondEscalationAccounting.pledge to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IBondEscalationAccounting.pledge, (address(this), mockRequest, _dispute, _params.bondToken, _params.bondSize)
      ),
      abi.encode(true)
    );

    // Check: is event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit PledgedForDispute(_disputeId, address(this), _params.bondSize);

    bondEscalationModule.pledgeForDispute(mockRequest, _dispute);

    uint256 _pledgesForDispute = bondEscalationModule.getEscalation(_requestId).amountOfPledgesForDispute;
    // Check: is the number of pledges for the dispute properly updated?
    assertEq(_pledgesForDispute, _numForPledgers + 1);

    uint256 _userPledges = bondEscalationModule.pledgesForDispute(_requestId, address(this));
    // Check: is the number of pledges for the user properly updated?
    assertEq(_userPledges, 1);
  }
}

contract BondEscalationModule_Unit_PledgeAgainstDispute is BaseTest {
  /**
   * @notice Tests that pledgeAgainstDispute reverts if the dispute body is invalid.
   */
  function test_revertIfInvalidDisputeBody() public {
    // Check: does it revert if the dispute body is invalid?
    vm.expectRevert(ValidatorLib.ValidatorLib_InvalidDisputeBody.selector);
    bondEscalationModule.pledgeAgainstDispute(mockRequest, mockDispute);
  }

  /**
   * @notice Tests that pledgeAgainstDispute reverts if the dispute is not going through the bond escalation mechanism.
   */
  function test_revertIfTheDisputeIsNotGoingThroughTheBondEscalationProcess() public {
    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);

    // Check: does it revert if the dispute is not escalated yet?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_InvalidDispute.selector);
    bondEscalationModule.pledgeAgainstDispute(mockRequest, _dispute);
  }

  /**
   * @notice Tests that pledgeAgainstDispute reverts if someone tries to pledge after the tying buffer.
   */
  function test_revertIfTimestampBeyondTyingBuffer(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    _params.bondSize = 1;
    _params.maxNumberOfEscalations = 1;
    _params.bondEscalationDeadline = block.timestamp;
    _params.tyingBuffer = 1000;
    mockRequest.disputeModuleData = abi.encode(_params);

    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    vm.warp(_params.bondEscalationDeadline + _params.tyingBuffer + 1);

    // Check: does it revert if the bond escalation is over?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationOver.selector);

    bondEscalationModule.pledgeAgainstDispute(mockRequest, _dispute);
  }

  /**
   * @notice Tests that pledgeAgainstDispute reverts if the maximum number of escalations has been reached.
   */
  function test_revertIfMaxNumberOfEscalationsReached(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    _params.bondSize = 1;
    _params.maxNumberOfEscalations = 2;
    _params.bondEscalationDeadline = block.timestamp - 1;
    _params.tyingBuffer = 1000;
    mockRequest.disputeModuleData = abi.encode(_params);

    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = _numForPledgers;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    // Check: does it revert if the maximum number of escalations is reached?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_MaxNumberOfEscalationsReached.selector);

    bondEscalationModule.pledgeAgainstDispute(mockRequest, _dispute);
  }

  /**
   * @notice Tests that pledgeAgainstDispute reverts if someone tries to pledge in favor of the dispute when there are
   *         more pledges against of the dispute than in favor of it
   */
  function test_revertIfThereIsMorePledgedAgainstDisputeThanFor(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    _params.tyingBuffer = bound(_params.tyingBuffer, 0, type(uint128).max);
    _params.bondSize = 1;
    _params.maxNumberOfEscalations = 3;
    _params.bondEscalationDeadline = block.timestamp + 1;
    mockRequest.disputeModuleData = abi.encode(_params);

    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _numAgainstPledgers = 2;
    uint256 _numForPledgers = _numAgainstPledgers - 1;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    // Check: does it revert if trying to pledge in a dispute that is already surpassed?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_CanOnlySurpassByOnePledge.selector);

    bondEscalationModule.pledgeAgainstDispute(mockRequest, _dispute);
  }

  /**
   * @notice Tests that pledgeAgainstDispute reverts if the timestamp is within the tying buffer and someone attempts
   *         to pledge when the funds are tied, effectively breaking the tie
   */
  function test_revertIfAttemptToBreakTieDuringTyingBuffer(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    // Set mock request parameters
    _params.bondSize = 1;
    _params.maxNumberOfEscalations = 3;
    _params.bondEscalationDeadline = block.timestamp - 1;
    _params.tyingBuffer = 1000;
    mockRequest.disputeModuleData = abi.encode(_params);

    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = _numForPledgers;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    // Check: does it revert if trying to tie outside of the tying buffer?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_CannotBreakTieDuringTyingBuffer.selector);
    bondEscalationModule.pledgeAgainstDispute(mockRequest, _dispute);
  }

  /**
   * @notice Tests that pledgeAgainstDispute is called successfully
   */
  function test_successfulCall(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    _params.bondSize = 1000;
    _params.maxNumberOfEscalations = 3;
    _params.bondEscalationDeadline = block.timestamp - 1;
    _params.tyingBuffer = 1000;
    mockRequest.disputeModuleData = abi.encode(_params);

    (, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _numAgainstPledgers = 2;
    uint256 _numForPledgers = _numAgainstPledgers + 1;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IBondEscalationAccounting.pledge, (address(this), mockRequest, _dispute, _params.bondToken, _params.bondSize)
      ),
      abi.encode(true)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit PledgedAgainstDispute(_disputeId, address(this), _params.bondSize);

    bondEscalationModule.pledgeAgainstDispute(mockRequest, _dispute);

    uint256 _pledgesForDispute = bondEscalationModule.getEscalation(_requestId).amountOfPledgesAgainstDispute;
    // Check: is the number of pledges for the dispute properly updated?
    assertEq(_pledgesForDispute, _numAgainstPledgers + 1);

    uint256 _userPledges = bondEscalationModule.pledgesAgainstDispute(_requestId, address(this));
    // Check: is the number of pledges for the user properly updated?
    assertEq(_userPledges, 1);
  }
}

contract BondEscalationModule_Unit_SettleBondEscalation is BaseTest {
  /**
   * @notice Tests that settleBondEscalation reverts if the response body is invalid.
   */
  function test_revertIfInvalidResponseBody() public {
    // Check: does it revert if the response body is invalid?
    vm.expectRevert(ValidatorLib.ValidatorLib_InvalidResponseBody.selector);
    bondEscalationModule.settleBondEscalation(mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Tests that settleBondEscalation reverts if the dispute body is invalid.
   */
  function test_revertIfInvalidDisputeBody() public {
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;

    // Check: does it revert if the dispute body is invalid?
    vm.expectRevert(ValidatorLib.ValidatorLib_InvalidDisputeBody.selector);
    bondEscalationModule.settleBondEscalation(mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Tests that settleBondEscalation reverts if someone tries to settle the escalation before the tying buffer
   *         has elapsed.
   */
  function test_revertIfTimestampLessThanEndOfTyingBuffer(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    _params.tyingBuffer = bound(_params.tyingBuffer, 0, type(uint128).max);
    _params.bondEscalationDeadline = block.timestamp;
    mockRequest.disputeModuleData = abi.encode(_params);

    (IOracle.Response memory _response, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);

    // Check: does it revert if the bond escalation is not over?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationNotOver.selector);
    bondEscalationModule.settleBondEscalation(mockRequest, _response, _dispute);
  }

  /**
   * @notice Tests that settleBondEscalation reverts if someone tries to settle a bond-escalated dispute that
   *         is not active.
   */
  function test_revertIfStatusOfBondEscalationIsNotActive(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    _params.bondEscalationDeadline = block.timestamp;
    _params.tyingBuffer = 1000;
    mockRequest.disputeModuleData = abi.encode(_params);

    (IOracle.Response memory _response, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);

    vm.warp(_params.bondEscalationDeadline + _params.tyingBuffer + 1);

    bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.None);

    // Check: does it revert if the bond escalation is not active?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationCantBeSettled.selector);
    bondEscalationModule.settleBondEscalation(mockRequest, _response, _dispute);
  }

  /**
   * @notice Tests that settleBondEscalation reverts if someone tries to settle a bond-escalated dispute that
   *         has the same number of pledgers.
   */
  function test_revertIfSameNumberOfPledgers(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    _params.bondEscalationDeadline = block.timestamp;
    _params.tyingBuffer = 1000;
    mockRequest.disputeModuleData = abi.encode(_params);

    (IOracle.Response memory _response, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    vm.warp(_params.bondEscalationDeadline + _params.tyingBuffer + 1);

    bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _numForPledgers = 5;
    uint256 _numAgainstPledgers = _numForPledgers;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    // Check: does it revert if the number of pledgers is the same?
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_ShouldBeEscalated.selector);
    bondEscalationModule.settleBondEscalation(mockRequest, _response, _dispute);
  }

  /**
   * @notice Tests that settleBondEscalation is called successfully.
   */
  function test_successfulCallDisputerWon(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    _params.bondSize = 1000;
    _params.bondEscalationDeadline = block.timestamp;
    _params.tyingBuffer = 1000;
    mockRequest.disputeModuleData = abi.encode(_params);

    (IOracle.Response memory _response, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    vm.warp(_params.bondEscalationDeadline + _params.tyingBuffer + 1);

    bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _numForPledgers = 2;
    uint256 _numAgainstPledgers = _numForPledgers - 1;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    _mockAndExpect(
      address(oracle),
      abi.encodeCall(IOracle.updateDisputeStatus, (mockRequest, _response, _dispute, IOracle.DisputeStatus.Won)),
      abi.encode(true)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.DisputerWon);

    bondEscalationModule.settleBondEscalation(mockRequest, _response, _dispute);
    // Check: is the bond escalation status properly updated?
    assertEq(
      uint256(bondEscalationModule.getEscalation(_requestId).status),
      uint256(IBondEscalationModule.BondEscalationStatus.DisputerWon)
    );
  }

  /**
   * @notice Tests that settleBondEscalation is called successfully.
   */
  function test_successfulCallDisputerLost(IBondEscalationModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    _params.bondSize = 1000;
    _params.bondEscalationDeadline = block.timestamp;
    _params.tyingBuffer = 1000;
    mockRequest.disputeModuleData = abi.encode(_params);

    (IOracle.Response memory _response, IOracle.Dispute memory _dispute) = _getResponseAndDispute(oracle);
    bytes32 _requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(_dispute);

    vm.warp(_params.bondEscalationDeadline + _params.tyingBuffer + 1);

    bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);
    bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

    uint256 _numAgainstPledgers = 2;
    uint256 _numForPledgers = _numAgainstPledgers - 1;

    _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

    _mockAndExpect(
      address(oracle),
      abi.encodeCall(IOracle.updateDisputeStatus, (mockRequest, _response, _dispute, IOracle.DisputeStatus.Lost)),
      abi.encode(true)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondEscalationModule));
    emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.DisputerLost);

    bondEscalationModule.settleBondEscalation(mockRequest, _response, _dispute);
    // Check: is the bond escalation status properly updated?
    assertEq(
      uint256(bondEscalationModule.getEscalation(_requestId).status),
      uint256(IBondEscalationModule.BondEscalationStatus.DisputerLost)
    );
  }
}
