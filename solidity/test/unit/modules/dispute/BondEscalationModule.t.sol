// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity ^0.8.19;

// import 'forge-std/Test.sol';

// import {Helpers} from '../../../utils/Helpers.sol';

// import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
// import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';
// import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
// import {IModule} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IModule.sol';

// import {
//   BondEscalationModule, IBondEscalationModule
// } from '../../../../contracts/modules/dispute/BondEscalationModule.sol';

// import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';
// import {IBondEscalationAccounting} from '../../../../interfaces/extensions/IBondEscalationAccounting.sol';

// /**
//  * @dev Harness to set an entry in the requestData mapping, without triggering setup request hooks
//  */
// contract ForTest_BondEscalationModule is BondEscalationModule {
//   constructor(IOracle _oracle) BondEscalationModule(_oracle) {}

//   function forTest_setRequestData(bytes32 _requestId, bytes memory _data) public {
//     requestData[_requestId] = _data;
//   }

//   function forTest_setBondEscalation(
//     bytes32 _requestId,
//     address[] memory _pledgersForDispute,
//     address[] memory _pledgersAgainstDispute
//   ) public {
//     for (uint256 _i; _i < _pledgersForDispute.length; _i++) {
//       pledgesForDispute[_requestId][_pledgersForDispute[_i]] += 1;
//     }

//     for (uint256 _i; _i < _pledgersAgainstDispute.length; _i++) {
//       pledgesAgainstDispute[_requestId][_pledgersAgainstDispute[_i]] += 1;
//     }

//     _escalations[_requestId].amountOfPledgesForDispute += _pledgersForDispute.length;
//     _escalations[_requestId].amountOfPledgesAgainstDispute += _pledgersAgainstDispute.length;
//   }

//   function forTest_setBondEscalationStatus(
//     bytes32 _requestId,
//     BondEscalationModule.BondEscalationStatus _bondEscalationStatus
//   ) public {
//     _escalations[_requestId].status = _bondEscalationStatus;
//   }

//   function forTest_setEscalatedDispute(bytes32 _requestId, bytes32 _disputeId) public {
//     _escalations[_requestId].disputeId = _disputeId;
//   }
// }

// /**
//  * @title Bonded Response Module Unit tests
//  */

// contract BaseTest is Test, Helpers {
//   // The target contract
//   ForTest_BondEscalationModule public bondEscalationModule;
//   // A mock oracle
//   IOracle public oracle;
//   // A mock accounting extension
//   IBondEscalationAccounting public accounting;
//   // A mock token
//   IERC20 public token;
//   // Mock EOA proposer
//   address public proposer = makeAddr('proposer');
//   // Mock EOA disputer
//   address public disputer = makeAddr('disputer');
//   // Mock bondSize
//   uint256 public bondSize;
//   // Mock max number of escalations
//   uint256 public maxEscalations;
//   // Mock bond escalation deadline
//   uint256 public bondEscalationDeadline;
//   // Mock tyingBuffer
//   uint256 public tyingBuffer;
//   // Mock dispute window
//   uint256 public disputeWindow;
//   // Mock dispute
//   IOracle.Dispute internal _mockDispute;
//   // Mock response
//   IOracle.Response internal _mockResponse;

//   // Events
//   event PledgedForDispute(bytes32 indexed _disputeId, address indexed _pledger, uint256 indexed _amount);
//   event PledgedAgainstDispute(bytes32 indexed _disputeId, address indexed _pledger, uint256 indexed _amount);
//   event BondEscalationStatusUpdated(
//     bytes32 indexed _requestId, bytes32 indexed _disputeId, IBondEscalationModule.BondEscalationStatus _status
//   );
//   event ResponseDisputed(bytes32 indexed _requestId, bytes32 _responseId, address _disputer, address _proposer);
//   event DisputeStatusChanged(
//     bytes32 indexed _requestId, bytes32 _responseId, address _disputer, address _proposer, IOracle.DisputeStatus _status
//   );

//   /**
//    * @notice Deploy the target and mock oracle+accounting extension
//    */
//   function setUp() public {
//     oracle = IOracle(makeAddr('Oracle'));
//     vm.etch(address(oracle), hex'069420');

//     accounting = IBondEscalationAccounting(makeAddr('BondEscalationAccounting'));
//     vm.etch(address(accounting), hex'069420');

//     token = IERC20(makeAddr('ERC20'));
//     vm.etch(address(token), hex'069420');

//     // Set to an arbitrary large value to avoid unintended reverts
//     disputeWindow = type(uint128).max;

//     // Avoid starting at 0 for time sensitive tests
//     vm.warp(123_456);

//     _mockDispute = IOracle.Dispute({
//       disputer: disputer,
//       responseId: bytes32('response'),
//       proposer: proposer,
//       requestId: bytes32('69'),
//       status: IOracle.DisputeStatus.Active,
//       createdAt: block.timestamp
//     });

//     _mockResponse = IOracle.Response({
//       createdAt: block.timestamp,
//       proposer: proposer,
//       requestId: bytes32('69'),
//       disputeId: 0,
//       response: abi.encode(bytes32('response'))
//     });

//     bondEscalationModule = new ForTest_BondEscalationModule(oracle);
//   }

//   function _setRequestData(
//     bytes32 _requestId,
//     uint256 _bondSize,
//     uint256 _maxNumberOfEscalations,
//     uint256 _bondEscalationDeadline,
//     uint256 _tyingBuffer,
//     uint256 _disputeWindow
//   ) internal {
//     bytes memory _data = abi.encode(
//       IBondEscalationModule.RequestParameters({
//         accountingExtension: accounting,
//         bondToken: token,
//         bondSize: _bondSize,
//         maxNumberOfEscalations: _maxNumberOfEscalations,
//         bondEscalationDeadline: _bondEscalationDeadline,
//         tyingBuffer: _tyingBuffer,
//         disputeWindow: _disputeWindow
//       })
//     );
//     bondEscalationModule.forTest_setRequestData(_requestId, _data);
//   }

//   function _getRandomDispute(
//     bytes32 _requestId,
//     IOracle.DisputeStatus _status
//   ) internal view returns (IOracle.Dispute memory _dispute) {
//     _dispute = IOracle.Dispute({
//       disputer: disputer,
//       responseId: bytes32('response'),
//       proposer: proposer,
//       requestId: _requestId,
//       status: _status,
//       createdAt: block.timestamp
//     });
//   }

//   function _setBondEscalation(
//     bytes32 _requestId,
//     uint256 _numForPledgers,
//     uint256 _numAgainstPledgers
//   ) internal returns (address[] memory _forPledgers, address[] memory _againstPledgers) {
//     _forPledgers = new address[](_numForPledgers);
//     _againstPledgers = new address[](_numAgainstPledgers);
//     address _forPledger;
//     address _againstPledger;

//     for (uint256 _i; _i < _numForPledgers; _i++) {
//       _forPledger = makeAddr(string.concat('forPledger', Strings.toString(_i)));
//       _forPledgers[_i] = _forPledger;
//     }

//     for (uint256 _j; _j < _numAgainstPledgers; _j++) {
//       _againstPledger = makeAddr(string.concat('againstPledger', Strings.toString(_j)));
//       _againstPledgers[_j] = _againstPledger;
//     }

//     bondEscalationModule.forTest_setBondEscalation(_requestId, _forPledgers, _againstPledgers);

//     return (_forPledgers, _againstPledgers);
//   }
// }

// contract BondEscalationModule_Unit_ModuleData is BaseTest {
//   /**
//    * @notice Test that the moduleName function returns the correct name
//    */
//   function test_moduleName() public {
//     assertEq(bondEscalationModule.moduleName(), 'BondEscalationModule');
//   }

//   /**
//    * @notice Tests that decodeRequestData decodes the data correctly
//    */
//   function test_decodeRequestDataReturnTheCorrectData(
//     bytes32 _requestId,
//     uint256 _bondSize,
//     uint256 _maxNumberOfEscalations,
//     uint256 _bondEscalationDeadline,
//     uint256 _tyingBuffer,
//     uint256 _disputeWindow
//   ) public {
//     _setRequestData(
//       _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, _disputeWindow
//     );
//     IBondEscalationModule.RequestParameters memory _params = bondEscalationModule.decodeRequestData(_requestId);

//     // Check: does the stored data match the provided one?
//     assertEq(address(accounting), address(_params.accountingExtension));
//     assertEq(address(token), address(_params.bondToken));
//     assertEq(_bondSize, _params.bondSize);
//     assertEq(_maxNumberOfEscalations, _params.maxNumberOfEscalations);
//     assertEq(_bondEscalationDeadline, _params.bondEscalationDeadline);
//     assertEq(_tyingBuffer, _params.tyingBuffer);
//     assertEq(_disputeWindow, _params.disputeWindow);
//   }
// }

// contract BondEscalationModule_Unit_EscalateDispute is BaseTest {
//   /**
//    * @notice Tests that escalateDispute reverts if the _disputeId doesn't match any existing disputes.
//    */
//   function test_revertOnInvalidDispute(bytes32 _disputeId) public {
//     _mockDispute.requestId = bytes32(0);
//     // Mock and expect Oracle.getDispute to be called.
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     // Check: does it revert if the dispute does not exist?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_DisputeDoesNotExist.selector);
//     vm.prank(address(oracle));
//     bondEscalationModule.disputeEscalated(_disputeId);
//   }

//   /**
//    * @notice Tests that escalateDispute reverts if the _disputeId doesn't match any existing disputes.
//    */
//   function test_revertOnInvalidParameters(
//     bytes32 _requestId,
//     uint256 _maxNumberOfEscalations,
//     uint256 _bondSize,
//     uint256 _bondEscalationDeadline,
//     uint256 _tyingBuffer,
//     uint256 _disputeWindow
//   ) public {
//     bytes memory _requestData = abi.encode(
//       IBondEscalationModule.RequestParameters({
//         accountingExtension: accounting,
//         bondToken: token,
//         bondSize: _bondSize,
//         maxNumberOfEscalations: _maxNumberOfEscalations,
//         bondEscalationDeadline: _bondEscalationDeadline,
//         tyingBuffer: _tyingBuffer,
//         disputeWindow: _disputeWindow
//       })
//     );

//     if (_maxNumberOfEscalations == 0 || _bondSize == 0) {
//       // Check: does it revert if _maxNumberOfEscalations or _bondSize is 0?
//       vm.expectRevert(IBondEscalationModule.BondEscalationModule_InvalidEscalationParameters.selector);
//     }

//     vm.prank(address(oracle));
//     bondEscalationModule.setupRequest(_requestId, _requestData);
//   }

//   /**
//    * @notice Tests that escalateDispute reverts if a dispute is escalated before the bond escalation deadline is over.
//    *         Conditions to reach this check:
//    *                                         - The _requestId tied to the dispute tied to _disputeId must be valid (non-zero)
//    *                                         - The block.timestamp has to be <= bond escalation deadline
//    */
//   function test_revertEscalationDuringBondEscalation(bytes32 _disputeId, bytes32 _requestId) public {
//     vm.assume(_requestId > 0);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect Oracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     // Set _bondEscalationDeadline to be the current timestamp to reach the second condition.
//     uint256 _bondEscalationDeadline = block.timestamp;

//     // Populate the requestData for the given requestId
//     _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, tyingBuffer, disputeWindow);

//     // Setting this dispute as the one going through the bond escalation process, as the user can only
//     // dispute once before the bond escalation deadline is over, and that dispute goes through the escalation module.
//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     // Check: does it revert if the bond escalation is not over yet?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationNotOver.selector);
//     vm.prank(address(oracle));
//     bondEscalationModule.disputeEscalated(_disputeId);
//   }

//   /**
//    * @notice Tests that escalateDispute reverts if a dispute that went through the bond escalation mechanism but isn't active
//    *         anymore is escalated.
//    *         Conditions to reach this check:
//    *             - The _requestId tied to the dispute tied to _disputeId must be valid (non-zero)
//    *             - The block.timestamp has to be > bond escalation deadline
//    *             - The dispute has to have gone through the bond escalation process before
//    *             - The status of the bond escalation mechanism has to be different from Active
//    */
//   function test_revertIfEscalatingNonActiveDispute(bytes32 _disputeId, bytes32 _requestId, uint8 _status) public {
//     // Assume _requestId is not zero
//     vm.assume(_requestId > 0);
//     // Assume the status will be any available other but Active
//     vm.assume(_status != uint8(IBondEscalationModule.BondEscalationStatus.Active) && _status < 4);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect Oracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     // Set a tying buffer to show that this can happen even in the tying buffer if the dispute was settled
//     uint256 _tyingBuffer = 1000;

//     // Make the current timestamp be greater than the bond escalation deadline
//     uint256 _bondEscalationDeadline = block.timestamp - 1;

//     // Populate the requestData for the given requestId
//     _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);

//     // Set the bond escalation status of the given requestId to something different than Active
//     bondEscalationModule.forTest_setBondEscalationStatus(
//       _requestId, IBondEscalationModule.BondEscalationStatus(_status)
//     );

//     // Set the dispute to be the one that went through the bond escalation process for the given requestId
//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     // Check: does it revert if the dispute is not escalatable?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_NotEscalatable.selector);
//     vm.prank(address(oracle));
//     bondEscalationModule.disputeEscalated(_disputeId);
//   }

//   /**
//    * @notice Tests that escalateDispute reverts if a dispute that went through the bond escalation mechanism and is still active
//    *         but its pledges are not tied even after the tying buffer is escalated.
//    *         Conditions to reach this check:
//    *             - The _requestId tied to the dispute tied to _disputeId must be valid (non-zero)
//    *             - The block.timestamp has to be > bond escalation deadline + tying buffer
//    *             - The dispute has to have gone or be going through the bond escalation process
//    *             - The pledges must not be tied
//    */
//   function test_revertIfEscalatingDisputeIsNotTied(bytes32 _disputeId, bytes32 _requestId) public {
//     // Assume _requestId is not zero
//     vm.assume(_requestId > 0);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect Oracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     // Set a tying buffer to make the test more explicit
//     uint256 _tyingBuffer = 1000;

//     // Set bond escalation deadline to be the current timestamp. We will warp this.
//     uint256 _bondEscalationDeadline = block.timestamp;

//     // Set the number of pledgers to be different
//     uint256 _numForPledgers = 1;
//     uint256 _numAgainstPledgers = 2;

//     // Warp the current timestamp so we are past the tyingBuffer
//     vm.warp(_bondEscalationDeadline + _tyingBuffer + 1);

//     // Populate the requestData for the given requestId
//     _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);

//     // Set the bond escalation status of the given requestId to Active
//     bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);

//     // Set the dispute to be the one that went through the bond escalation process for the given requestId
//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     // Set the number of pledgers for both sides
//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     // Check: does it revert if the dispute is not escalatable?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_NotEscalatable.selector);
//     vm.prank(address(oracle));
//     bondEscalationModule.disputeEscalated(_disputeId);
//   }

//   /**
//    * @notice Tests that escalateDispute escalates the dispute going through the bond escalation mechanism correctly when the
//    *         pledges are tied and the dispute is still active.
//    *         Conditions for the function to succeed:
//    *             - The _requestId tied to the dispute tied to _disputeId must be valid (non-zero)
//    *             - The block.timestamp has to be > bond escalation deadline
//    *             - The dispute has to have gone or be going through the bond escalation process
//    *             - The pledges must be tied
//    */
//   function test_escalateTiedDispute(bytes32 _disputeId, bytes32 _requestId) public {
//     // Assume _requestId is not zero
//     vm.assume(_requestId > 0);
//     vm.assume(_disputeId > 0);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect Oracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     // Set a tying buffer
//     uint256 _tyingBuffer = 1000;

//     // Set bond escalation deadline to be the current timestamp. We will warp this.
//     uint256 _bondEscalationDeadline = block.timestamp;

//     // Set the number of pledgers to be the same. This means the pledges are tied.
//     uint256 _numForPledgers = 2;
//     uint256 _numAgainstPledgers = 2;

//     // Warp so we are still in the tying buffer period. This is to show a dispute can be escalated during the buffer if the pledges are tied.
//     vm.warp(_bondEscalationDeadline + _tyingBuffer);

//     // Populate the requestData for the given requestId
//     _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);

//     // Set the bond escalation status of the given requestId to Active
//     bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);

//     // Set the dispute to be the one that went through the bond escalation process for the given requestId
//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     // Set the number of pledgers for both sides
//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(bondEscalationModule));
//     emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.Escalated);

//     vm.prank(address(oracle));
//     bondEscalationModule.disputeEscalated(_disputeId);

//     IBondEscalationModule.BondEscalation memory _escalation = bondEscalationModule.getEscalation(_requestId);
//     // Check: is the bond escalation status properly updated?
//     assertEq(uint256(_escalation.status), uint256(IBondEscalationModule.BondEscalationStatus.Escalated));
//   }

//   /**
//    * @notice Tests that escalateDispute escalates a dispute not going through the bond escalation mechanism correctly after
//    *         the bond mechanism deadline has gone by.
//    *         Conditions for the function to succeed:
//    *             - The _requestId tied to the dispute tied to _disputeId must be valid (non-zero)
//    *             - The block.timestamp has to be > bond escalation deadline
//    */
//   function test_escalateNormalDispute(bytes32 _disputeId, bytes32 _requestId) public {
//     // Assume _requestId and _disputeId are not zero
//     vm.assume(_requestId > 0);
//     vm.assume(_disputeId > 0);

//     uint256 _tyingBuffer = 1000;

//     _mockDispute.requestId = _requestId;

//     // Mock and expect Oracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     // Set bond escalation deadline to be the current timestamp. We will warp this.
//     uint256 _bondEscalationDeadline = block.timestamp;

//     // Warp so we are past the tying buffer period
//     vm.warp(_bondEscalationDeadline + 1);

//     // Populate the requestData for the given requestId
//     _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);

//     vm.prank(address(oracle));
//     bondEscalationModule.disputeEscalated(_disputeId);
//   }
// }

// contract BondEscalationModule_Unit_DisputeResponse is BaseTest {
//   /**
//    * @notice Tests that disputeResponse reverts the caller is not the oracle address.
//    */
//   function test_revertIfCallerIsNotOracle(bytes32 _requestId, bytes32 _responseId, address _caller) public {
//     vm.assume(_caller != address(oracle));

//     // Check: does it revert if not called by the Oracle?
//     vm.expectRevert(IModule.Module_OnlyOracle.selector);
//     vm.prank(_caller);
//     bondEscalationModule.disputeResponse(_requestId, _responseId, disputer, proposer);
//   }

//   /**
//    * @notice Tests that disputeResponse reverts if the challenge period for the response is over.
//    */
//   function test_revertIfDisputeWindowIsOver(bytes32 _requestId, bytes32 _responseId) public {
//     uint256 _disputeWindow = 1;

//     _setRequestData(_requestId, bondSize, maxEscalations, bondEscalationDeadline, tyingBuffer, _disputeWindow);

//     _mockResponse.requestId = _requestId;

//     // Mock and expect Oracle.getResponse to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)), abi.encode(_mockResponse));

//     // Warp to a time after the disputeWindow is over.
//     vm.warp(block.timestamp + _disputeWindow + 1);

//     // Check: does it revert if the dispute window is over?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_DisputeWindowOver.selector);
//     vm.prank(address(oracle));
//     bondEscalationModule.disputeResponse(_requestId, _responseId, disputer, proposer);
//   }

//   /**
//    * @notice Tests that disputeResponse succeeds if someone dispute after the bond escalation deadline is over
//    */
//   function test_succeedIfDisputeAfterBondingEscalationDeadline(bytes32 _requestId, bytes32 _responseId) public {
//     //  Set deadline to timestamp so we are still in the bond escalation period
//     uint256 _bondEscalationDeadline = block.timestamp - 1;

//     // Set the request data for the given requestId
//     _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, tyingBuffer, disputeWindow);

//     _mockResponse.requestId = _requestId;

//     // Mock and expect Oracle.getResponse to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)), abi.encode(_mockResponse));

//     // Check: does it revert if the bond escalation is over?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationOver.selector);
//     vm.prank(address(oracle));
//     bondEscalationModule.disputeResponse(_requestId, _responseId, disputer, proposer);
//   }

//   /**
//    * @notice Tests that disputeResponse succeeds in starting the bond escalation mechanism when someone disputes
//    *         the first propose before the bond escalation deadline is over.
//    */
//   function test_firstDisputeThroughBondMechanism(bytes32 _requestId, bytes32 _responseId) public {
//     //  Set deadline to timestamp so we are still in the bond escalation period
//     uint256 _bondEscalationDeadline = block.timestamp;

//     // Set the request data for the given requestId
//     _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, tyingBuffer, disputeWindow);

//     _mockResponse.requestId = _requestId;

//     // Mock and expect Oracle.getResponse to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)), abi.encode(_mockResponse));

//     // Mock and expect the accounting extension to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeWithSignature('bond(address,bytes32,address,uint256)', disputer, _requestId, token, bondSize),
//       abi.encode(true)
//     );

//     bytes32 _expectedDisputeId = keccak256(abi.encodePacked(disputer, _requestId, _responseId));

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(bondEscalationModule));
//     emit BondEscalationStatusUpdated(_requestId, _expectedDisputeId, IBondEscalationModule.BondEscalationStatus.Active);

//     vm.prank(address(oracle));
//     bondEscalationModule.disputeResponse(_requestId, _responseId, disputer, proposer);

//     // Check: is the bond escalation status now active?
//     assertEq(
//       uint256(bondEscalationModule.getEscalation(_requestId).status),
//       uint256(IBondEscalationModule.BondEscalationStatus.Active)
//     );

//     // Check: is the dispute assigned to the bond escalation process?
//     assertEq(bondEscalationModule.getEscalation(_requestId).disputeId, _expectedDisputeId);
//   }

//   function test_emitsEvent(bytes32 _requestId, bytes32 _responseId) public {
//     //  Set deadline to timestamp so we are still in the bond escalation period
//     uint256 _bondEscalationDeadline = block.timestamp;

//     // Set the request data for the given requestId
//     _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, tyingBuffer, disputeWindow);

//     _mockResponse.requestId = _requestId;

//     // Mock and expect Oracle.getResponse to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)), abi.encode(_mockResponse));

//     // Mock and expect the accounting extension to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeWithSignature('bond(address,bytes32,address,uint256)', disputer, _requestId, token, bondSize),
//       abi.encode(true)
//     );

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(bondEscalationModule));
//     emit ResponseDisputed(_requestId, _responseId, disputer, proposer);

//     vm.prank(address(oracle));
//     bondEscalationModule.disputeResponse(_requestId, _responseId, disputer, proposer);
//   }
// }

// contract BondEscalationModule_Unit_OnDisputeStatusChange is BaseTest {
//   /**
//    * @notice Tests that onDisputeStatusChange reverts
//    */
//   function test_revertIfCallerIsNotOracle(
//     bytes32 _disputeId,
//     bytes32 _requestId,
//     address _caller,
//     uint8 _status
//   ) public {
//     vm.assume(_caller != address(oracle));
//     vm.assume(_status < 4);

//     IOracle.DisputeStatus _disputeStatus = IOracle.DisputeStatus(_status);
//     IOracle.Dispute memory _dispute = _getRandomDispute(_requestId, _disputeStatus);

//     // Check: does it revert if not called by the Oracle?
//     vm.expectRevert(IModule.Module_OnlyOracle.selector);
//     vm.prank(_caller);
//     bondEscalationModule.onDisputeStatusChange(_disputeId, _dispute);
//   }

//   /**
//    * @notice Tests that onDisputeStatusChange pays the proposer if the disputer lost
//    */
//   function test_callPayIfNormalDisputeLost(bytes32 _disputeId, bytes32 _requestId) public {
//     vm.assume(_disputeId > 0 && _requestId > 0);

//     IOracle.DisputeStatus _status = IOracle.DisputeStatus.Lost;
//     IOracle.Dispute memory _dispute = _getRandomDispute(_requestId, _status);

//     _setRequestData(_requestId, bondSize, maxEscalations, bondEscalationDeadline, tyingBuffer, disputeWindow);

//     // Mock and expect IAccountingExtension.pay to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.disputer, _dispute.proposer, token, bondSize)),
//       abi.encode(true)
//     );

//     vm.prank(address(oracle));
//     bondEscalationModule.onDisputeStatusChange(_disputeId, _dispute);
//   }

//   /**
//    * @notice Tests that onDisputeStatusChange pays the disputer if the disputer won
//    */
//   function test_callPayIfNormalDisputeWon(bytes32 _disputeId, bytes32 _requestId) public {
//     IOracle.DisputeStatus _status = IOracle.DisputeStatus.Won;
//     IOracle.Dispute memory _dispute = _getRandomDispute(_requestId, _status);

//     _setRequestData(_requestId, bondSize, maxEscalations, bondEscalationDeadline, tyingBuffer, disputeWindow);

//     // Mock and expect IAccountingExtension.pay to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.proposer, _dispute.disputer, token, bondSize)),
//       abi.encode(true)
//     );

//     // Mock and expect IAccountingExtension.release to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(IAccountingExtension.release, (_dispute.disputer, _requestId, token, bondSize)),
//       abi.encode(true)
//     );

//     vm.prank(address(oracle));
//     bondEscalationModule.onDisputeStatusChange(_disputeId, _dispute);
//   }

//   function test_emitsEvent(bytes32 _disputeId, bytes32 _requestId) public {
//     IOracle.DisputeStatus _status = IOracle.DisputeStatus.Won;
//     IOracle.Dispute memory _dispute = _getRandomDispute(_requestId, _status);

//     _setRequestData(_requestId, bondSize, maxEscalations, bondEscalationDeadline, tyingBuffer, disputeWindow);

//     // Mock and expect IAccountingExtension.pay to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.proposer, _dispute.disputer, token, bondSize)),
//       abi.encode(true)
//     );

//     // Mock and expect IAccountingExtension.release to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(IAccountingExtension.release, (_dispute.disputer, _requestId, token, bondSize)),
//       abi.encode(true)
//     );

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(bondEscalationModule));
//     emit DisputeStatusChanged(
//       _requestId, _dispute.responseId, _dispute.disputer, _dispute.proposer, IOracle.DisputeStatus.Won
//     );

//     vm.prank(address(oracle));
//     bondEscalationModule.onDisputeStatusChange(_disputeId, _dispute);
//   }

//   /**
//    * @notice Tests that onDisputeStatusChange returns early if the dispute has gone through the bond
//    *         escalation mechanism but no one pledged
//    */
//   function test_earlyReturnIfBondEscalatedDisputeHashNoPledgers(bytes32 _disputeId, bytes32 _requestId) public {
//     IOracle.DisputeStatus _status = IOracle.DisputeStatus.Won;
//     IOracle.Dispute memory _dispute = _getRandomDispute(_requestId, _status);

//     _setRequestData(_requestId, bondSize, maxEscalations, bondEscalationDeadline, tyingBuffer, disputeWindow);

//     uint256 _numForPledgers = 0;
//     uint256 _numAgainstPledgers = 0;

//     // Set bond escalation data to have no pledgers
//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     // Set this dispute to have gone through the bond escalation process
//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     // Set the bond escalation status to Escalated, which is the only possible one for this function
//     bondEscalationModule.forTest_setBondEscalationStatus(
//       _requestId, IBondEscalationModule.BondEscalationStatus.Escalated
//     );

//     // Mock and expect IAccountingExtension.pay to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.proposer, _dispute.disputer, token, bondSize)),
//       abi.encode(true)
//     );

//     // Mock and expect IAccountingExtension.release to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(IAccountingExtension.release, (_dispute.disputer, _requestId, token, bondSize)),
//       abi.encode(true)
//     );

//     vm.prank(address(oracle));
//     bondEscalationModule.onDisputeStatusChange(_disputeId, _dispute);

//     // Check: is the bond escalation status properly updated?
//     assertEq(
//       uint256(bondEscalationModule.getEscalation(_requestId).status),
//       uint256(IBondEscalationModule.BondEscalationStatus.Escalated)
//     );
//   }

//   /**
//    * @notice Tests that onDisputeStatusChange changes the status of the bond escalation if the
//    *         dispute went through the bond escalation process, as well as testing that it calls
//    *         payPledgersWon with the correct arguments. In the Won case, this would be, passing
//    *         the users that pledged in favor of the dispute, as they have won.
//    */
//   function test_shouldChangeBondEscalationStatusAndCallPayPledgersWon(bytes32 _disputeId, bytes32 _requestId) public {
//     IOracle.DisputeStatus _status = IOracle.DisputeStatus.Won;
//     IOracle.Dispute memory _dispute = _getRandomDispute(_requestId, _status);

//     _setRequestData(_requestId, bondSize, maxEscalations, bondEscalationDeadline, tyingBuffer, disputeWindow);

//     uint256 _numForPledgers = 2;
//     uint256 _numAgainstPledgers = 2;

//     // Set bond escalation data to have pledgers and to return the winning for pledgers as in this case they won the escalation
//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     // Set this dispute to have gone through the bond escalation process
//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     // Set the bond escalation status to Escalated, which is the only possible one for this function
//     bondEscalationModule.forTest_setBondEscalationStatus(
//       _requestId, IBondEscalationModule.BondEscalationStatus.Escalated
//     );

//     // Mock and expect IAccountingExtension.pay to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.proposer, _dispute.disputer, token, bondSize)),
//       abi.encode(true)
//     );

//     // Mock and expect IAccountingExtension.release to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(IAccountingExtension.release, (_dispute.disputer, _requestId, token, bondSize)),
//       abi.encode(true)
//     );

//     // Mock and expect IBondEscalationAccounting.onSettleBondEscalation to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(
//         IBondEscalationAccounting.onSettleBondEscalation,
//         (_requestId, _disputeId, true, token, bondSize << 1, _numForPledgers)
//       ),
//       abi.encode()
//     );

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(bondEscalationModule));
//     emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.DisputerWon);

//     vm.prank(address(oracle));
//     bondEscalationModule.onDisputeStatusChange(_disputeId, _dispute);

//     // Check: is the bond escalation status properly updated?
//     assertEq(
//       uint256(bondEscalationModule.getEscalation(_requestId).status),
//       uint256(IBondEscalationModule.BondEscalationStatus.DisputerWon)
//     );
//   }

//   /**
//    * @notice Tests that onDisputeStatusChange changes the status of the bond escalation if the
//    *         dispute went through the bond escalation process, as well as testing that it calls
//    *         payPledgersWon with the correct arguments. In the Lost case, this would be, passing
//    *         the users that pledged against the dispute, as those that pledged in favor have lost .
//    */
//   function test_shouldChangeBondEscalationStatusAndCallPayPledgersLost(bytes32 _disputeId, bytes32 _requestId) public {
//     // Set to Lost so the proposer and againstDisputePledgers win
//     IOracle.DisputeStatus _status = IOracle.DisputeStatus.Lost;
//     IOracle.Dispute memory _dispute = _getRandomDispute(_requestId, _status);

//     uint256 _bondSize = 1000;

//     _setRequestData(_requestId, _bondSize, maxEscalations, bondEscalationDeadline, tyingBuffer, disputeWindow);

//     uint256 _numForPledgers = 2;
//     uint256 _numAgainstPledgers = 2;

//     // Set bond escalation data to have pledgers and to return the winning for pledgers as in this case they won the escalation
//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     // Set this dispute to have gone through the bond escalation process
//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     // Set the bond escalation status to Escalated, which is the only possible one for this function
//     bondEscalationModule.forTest_setBondEscalationStatus(
//       _requestId, IBondEscalationModule.BondEscalationStatus.Escalated
//     );

//     // Mock and expect IAccountingExtension.pay to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(IAccountingExtension.pay, (_requestId, _dispute.disputer, _dispute.proposer, token, _bondSize)),
//       abi.encode(true)
//     );

//     // Mock and expect IBondEscalationAccounting.onSettleBondEscalation to be called
//     vm.mockCall(
//       address(accounting),
//       abi.encodeCall(
//         IBondEscalationAccounting.onSettleBondEscalation,
//         (_requestId, _disputeId, false, token, _bondSize << 1, _numAgainstPledgers)
//       ),
//       abi.encode(true)
//     );

//     // Check: is th event emitted?
//     vm.expectEmit(true, true, true, true, address(bondEscalationModule));
//     emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.DisputerLost);

//     vm.prank(address(oracle));
//     bondEscalationModule.onDisputeStatusChange(_disputeId, _dispute);

//     // Check: is the bond escalation status properly updated?
//     assertEq(
//       uint256(bondEscalationModule.getEscalation(_requestId).status),
//       uint256(IBondEscalationModule.BondEscalationStatus.DisputerLost)
//     );
//   }
// }

// contract BondEscalationModule_Unit_PledgeForDispute is BaseTest {
//   /**
//    * @notice Tests that pledgeForDispute reverts if the dispute does not exist.
//    */
//   function test_revertIfDisputeIsZero() public {
//     bytes32 _disputeId = 0;

//     // Check: does it revert if the dispute does not exist?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_DisputeDoesNotExist.selector);
//     bondEscalationModule.pledgeForDispute(_disputeId);
//   }

//   /**
//    * @notice Tests that pledgeForDispute reverts if the dispute is not going through the bond escalation mechanism.
//    */
//   function test_revertIfTheDisputeIsNotGoingThroughTheBondEscalationProcess(
//     bytes32 _disputeId,
//     bytes32 _requestId
//   ) public {
//     vm.assume(_disputeId > 0);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect IOracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     // Check: does it revert if the dispute is not escalated yet?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_InvalidDispute.selector);
//     bondEscalationModule.pledgeForDispute(_disputeId);
//   }

//   /**
//    * @notice Tests that pledgeForDispute reverts if someone tries to pledge after the tying buffer.
//    */
//   function test_revertIfTimestampBeyondTyingBuffer(bytes32 _disputeId, bytes32 _requestId) public {
//     vm.assume(_disputeId > 0);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect IOracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     uint256 _bondSize = 1;
//     uint256 _maxNumberOfEscalations = 1;
//     uint256 _bondEscalationDeadline = block.timestamp;
//     uint256 _tyingBuffer = 1000;

//     vm.warp(_bondEscalationDeadline + _tyingBuffer + 1);

//     _setRequestData(
//       _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
//     );

//     // Check: does it revert if the bond escalation is over?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationOver.selector);
//     bondEscalationModule.pledgeForDispute(_disputeId);
//   }

//   /**
//    * @notice Tests that pledgeForDispute reverts if the maximum number of escalations has been reached.
//    */
//   function test_revertIfMaxNumberOfEscalationsReached(bytes32 _disputeId, bytes32 _requestId) public {
//     vm.assume(_disputeId > 0);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect IOracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     uint256 _bondSize = 1;
//     uint256 _maxNumberOfEscalations = 2;
//     uint256 _bondEscalationDeadline = block.timestamp - 1;
//     uint256 _tyingBuffer = 1000;

//     _setRequestData(
//       _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
//     );

//     uint256 _numForPledgers = 2;
//     uint256 _numAgainstPledgers = _numForPledgers;

//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     // Check: does it revert if the maximum number of escalations is reached?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_MaxNumberOfEscalationsReached.selector);
//     bondEscalationModule.pledgeForDispute(_disputeId);
//   }

//   /**
//    * @notice Tests that pledgeForDispute reverts if someone tries to pledge in favor of the dispute when there are
//    *         more pledges in favor of the dispute than against
//    */
//   function test_revertIfThereIsMorePledgedForForDisputeThanAgainst(bytes32 _disputeId, bytes32 _requestId) public {
//     vm.assume(_disputeId > 0);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect IOracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     uint256 _bondSize = 1;
//     uint256 _maxNumberOfEscalations = 3;
//     uint256 _bondEscalationDeadline = block.timestamp + 1;

//     _setRequestData(_requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, tyingBuffer, disputeWindow);

//     uint256 _numForPledgers = 2;
//     uint256 _numAgainstPledgers = _numForPledgers - 1;

//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     // Check: does it revert if trying to pledge in a dispute that is already surpassed?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_CanOnlySurpassByOnePledge.selector);
//     bondEscalationModule.pledgeForDispute(_disputeId);
//   }

//   /**
//    * @notice Tests that pledgeForDispute reverts if the timestamp is within the tying buffer and someone attempts
//    *         to pledge when the funds are tied, effectively breaking the tie
//    */
//   function test_revertIfAttemptToBreakTieDuringTyingBuffer(bytes32 _disputeId, bytes32 _requestId) public {
//     vm.assume(_disputeId > 0);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect IOracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     uint256 _bondSize = 1;
//     uint256 _maxNumberOfEscalations = 3;
//     uint256 _bondEscalationDeadline = block.timestamp - 1;
//     uint256 _tyingBuffer = 1000;

//     _setRequestData(
//       _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
//     );

//     uint256 _numForPledgers = 2;
//     uint256 _numAgainstPledgers = _numForPledgers;

//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     // Check: does it revert if trying to tie outside of the tying buffer?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_CannotBreakTieDuringTyingBuffer.selector);
//     bondEscalationModule.pledgeForDispute(_disputeId);
//   }

//   /**
//    * @notice Tests that pledgeForDispute is called successfully
//    */
//   function test_successfulCall(bytes32 _disputeId, bytes32 _requestId) public {
//     vm.assume(_disputeId > 0);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));
//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     uint256 _bondSize = 1000;
//     uint256 _maxNumberOfEscalations = 3;
//     uint256 _bondEscalationDeadline = block.timestamp - 1;
//     uint256 _tyingBuffer = 1000;

//     _setRequestData(
//       _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
//     );

//     uint256 _numForPledgers = 2;
//     uint256 _numAgainstPledgers = _numForPledgers + 1;

//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     // Mock and expect IBondEscalationAccounting.pledge to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(IBondEscalationAccounting.pledge, (address(this), _requestId, _disputeId, token, _bondSize)),
//       abi.encode(true)
//     );

//     // Check: is event emitted?
//     vm.expectEmit(true, true, true, true, address(bondEscalationModule));
//     emit PledgedForDispute(_disputeId, address(this), _bondSize);

//     bondEscalationModule.pledgeForDispute(_disputeId);

//     uint256 _pledgesForDispute = bondEscalationModule.getEscalation(_requestId).amountOfPledgesForDispute;
//     // Check: is the number of pledges for the dispute properly updated?
//     assertEq(_pledgesForDispute, _numForPledgers + 1);

//     uint256 _userPledges = bondEscalationModule.pledgesForDispute(_requestId, address(this));
//     // Check: is the number of pledges for the user properly updated?
//     assertEq(_userPledges, 1);
//   }
// }

// contract BondEscalationModule_Unit_PledgeAgainstDispute is BaseTest {
//   /**
//    * @notice Tests that pledgeAgainstDispute reverts if the dispute does not exist.
//    */
//   function test_revertIfDisputeIsZero() public {
//     bytes32 _disputeId = 0;

//     // Check: does it revert if the dispute does not exist?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_DisputeDoesNotExist.selector);
//     bondEscalationModule.pledgeAgainstDispute(_disputeId);
//   }

//   /**
//    * @notice Tests that pledgeAgainstDispute reverts if the dispute is not going through the bond escalation mechanism.
//    */
//   function test_revertIfTheDisputeIsNotGoingThroughTheBondEscalationProcess(
//     bytes32 _disputeId,
//     bytes32 _requestId
//   ) public {
//     vm.assume(_disputeId > 0);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect IOracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     // Check: does it revert if the dispute is not escalated yet?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_InvalidDispute.selector);
//     bondEscalationModule.pledgeAgainstDispute(_disputeId);
//   }

//   /**
//    * @notice Tests that pledgeAgainstDispute reverts if someone tries to pledge after the tying buffer.
//    */
//   function test_revertIfTimestampBeyondTyingBuffer(bytes32 _disputeId, bytes32 _requestId) public {
//     vm.assume(_disputeId > 0);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect IOracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     uint256 _bondSize = 1;
//     uint256 _maxNumberOfEscalations = 1;
//     uint256 _bondEscalationDeadline = block.timestamp;
//     uint256 _tyingBuffer = 1000;

//     vm.warp(_bondEscalationDeadline + _tyingBuffer + 1);

//     _setRequestData(
//       _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
//     );

//     // Check: does it revert if the bond escalation is over?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationOver.selector);

//     bondEscalationModule.pledgeAgainstDispute(_disputeId);
//   }

//   /**
//    * @notice Tests that pledgeAgainstDispute reverts if the maximum number of escalations has been reached.
//    */
//   function test_revertIfMaxNumberOfEscalationsReached(bytes32 _disputeId, bytes32 _requestId) public {
//     vm.assume(_disputeId > 0);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect IOracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     uint256 _bondSize = 1;
//     uint256 _maxNumberOfEscalations = 2;
//     uint256 _bondEscalationDeadline = block.timestamp - 1;
//     uint256 _tyingBuffer = 1000;

//     _setRequestData(
//       _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
//     );

//     uint256 _numForPledgers = 2;
//     uint256 _numAgainstPledgers = _numForPledgers;

//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     // Check: does it revert if the maximum number of escalations is reached?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_MaxNumberOfEscalationsReached.selector);

//     bondEscalationModule.pledgeAgainstDispute(_disputeId);
//   }

//   /**
//    * @notice Tests that pledgeAgainstDispute reverts if someone tries to pledge in favor of the dispute when there are
//    *         more pledges against of the dispute than in favor of it
//    */
//   function test_revertIfThereIsMorePledgedAgainstDisputeThanFor(bytes32 _disputeId, bytes32 _requestId) public {
//     vm.assume(_disputeId > 0);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect IOracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     uint256 _bondSize = 1;
//     uint256 _maxNumberOfEscalations = 3;
//     uint256 _bondEscalationDeadline = block.timestamp + 1;

//     _setRequestData(_requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, tyingBuffer, disputeWindow);

//     uint256 _numAgainstPledgers = 2;
//     uint256 _numForPledgers = _numAgainstPledgers - 1;

//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     // Check: does it revert if trying to pledge in a dispute that is already surpassed?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_CanOnlySurpassByOnePledge.selector);

//     bondEscalationModule.pledgeAgainstDispute(_disputeId);
//   }

//   /**
//    * @notice Tests that pledgeAgainstDispute reverts if the timestamp is within the tying buffer and someone attempts
//    *         to pledge when the funds are tied, effectively breaking the tie
//    */
//   function test_revertIfAttemptToBreakTieDuringTyingBuffer(bytes32 _disputeId, bytes32 _requestId) public {
//     vm.assume(_disputeId > 0);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect IOracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     uint256 _bondSize = 1;
//     uint256 _maxNumberOfEscalations = 3;
//     uint256 _bondEscalationDeadline = block.timestamp - 1;
//     uint256 _tyingBuffer = 1000;

//     _setRequestData(
//       _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
//     );

//     uint256 _numForPledgers = 2;
//     uint256 _numAgainstPledgers = _numForPledgers;

//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     // Check: does it revert if trying to tie outside of the tying buffer?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_CannotBreakTieDuringTyingBuffer.selector);
//     bondEscalationModule.pledgeAgainstDispute(_disputeId);
//   }

//   /**
//    * @notice Tests that pledgeAgainstDispute is called successfully
//    */
//   function test_successfulCall(bytes32 _disputeId, bytes32 _requestId) public {
//     vm.assume(_disputeId > 0);

//     _mockDispute.requestId = _requestId;

//     // Mock and expect IOracle.getDispute to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));

//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     uint256 _bondSize = 1000;
//     uint256 _maxNumberOfEscalations = 3;
//     uint256 _bondEscalationDeadline = block.timestamp - 1;
//     uint256 _tyingBuffer = 1000;

//     _setRequestData(
//       _requestId, _bondSize, _maxNumberOfEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow
//     );

//     uint256 _numAgainstPledgers = 2;
//     uint256 _numForPledgers = _numAgainstPledgers + 1;

//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(IBondEscalationAccounting.pledge, (address(this), _requestId, _disputeId, token, _bondSize)),
//       abi.encode(true)
//     );

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(bondEscalationModule));
//     emit PledgedAgainstDispute(_disputeId, address(this), _bondSize);

//     bondEscalationModule.pledgeAgainstDispute(_disputeId);

//     uint256 _pledgesForDispute = bondEscalationModule.getEscalation(_requestId).amountOfPledgesAgainstDispute;
//     // Check: is the number of pledges for the dispute properly updated?
//     assertEq(_pledgesForDispute, _numAgainstPledgers + 1);

//     uint256 _userPledges = bondEscalationModule.pledgesAgainstDispute(_requestId, address(this));
//     // Check: is the number of pledges for the user properly updated?
//     assertEq(_userPledges, 1);
//   }
// }

// contract BondEscalationModule_Unit_SettleBondEscalation is BaseTest {
//   /**
//    * @notice Tests that settleBondEscalation reverts if someone tries to settle the escalation before the tying buffer
//    *         has elapsed.
//    */
//   function test_revertIfTimestampLessThanEndOfTyingBuffer(bytes32 _requestId) public {
//     uint256 _bondEscalationDeadline = block.timestamp;
//     _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, tyingBuffer, disputeWindow);

//     // Check: does it revert if the bond escalation is not over?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationNotOver.selector);
//     bondEscalationModule.settleBondEscalation(_requestId);
//   }

//   /**
//    * @notice Tests that settleBondEscalation reverts if someone tries to settle a bond-escalated dispute that
//    *         is not active.
//    */
//   function test_revertIfStatusOfBondEscalationIsNotActive(bytes32 _requestId) public {
//     uint256 _bondEscalationDeadline = block.timestamp;
//     uint256 _tyingBuffer = 1000;

//     vm.warp(_bondEscalationDeadline + _tyingBuffer + 1);

//     _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);

//     bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.None);

//     // Check: does it revert if the bond escalation is not active?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationCantBeSettled.selector);
//     bondEscalationModule.settleBondEscalation(_requestId);
//   }

//   /**
//    * @notice Tests that settleBondEscalation reverts if someone tries to settle a bond-escalated dispute that
//    *         has the same number of pledgers.
//    */
//   function test_revertIfSameNumberOfPledgers(bytes32 _requestId, bytes32 _disputeId) public {
//     uint256 _bondEscalationDeadline = block.timestamp;
//     uint256 _tyingBuffer = 1000;

//     vm.warp(_bondEscalationDeadline + _tyingBuffer + 1);

//     _setRequestData(_requestId, bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);
//     bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);
//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     uint256 _numForPledgers = 5;
//     uint256 _numAgainstPledgers = _numForPledgers;

//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     // Check: does it revert if the number of pledgers is the same?
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_ShouldBeEscalated.selector);
//     bondEscalationModule.settleBondEscalation(_requestId);
//   }

//   /**
//    * @notice Tests that settleBondEscalation is called successfully.
//    */
//   function test_successfulCallDisputerWon(bytes32 _requestId, bytes32 _disputeId) public {
//     uint256 _bondSize = 1000;
//     uint256 _bondEscalationDeadline = block.timestamp;
//     uint256 _tyingBuffer = 1000;

//     vm.warp(_bondEscalationDeadline + _tyingBuffer + 1);

//     _setRequestData(_requestId, _bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);
//     bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);
//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     uint256 _numForPledgers = 2;
//     uint256 _numAgainstPledgers = _numForPledgers - 1;

//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     _mockAndExpect(
//       address(oracle),
//       abi.encodeCall(IOracle.updateDisputeStatus, (_disputeId, IOracle.DisputeStatus.Won)),
//       abi.encode(true)
//     );

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(bondEscalationModule));
//     emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.DisputerWon);

//     bondEscalationModule.settleBondEscalation(_requestId);
//     // Check: is the bond escalation status properly updated?
//     assertEq(
//       uint256(bondEscalationModule.getEscalation(_requestId).status),
//       uint256(IBondEscalationModule.BondEscalationStatus.DisputerWon)
//     );
//   }

//   /**
//    * @notice Tests that settleBondEscalation is called successfully.
//    */
//   function test_successfulCallDisputerLost(bytes32 _requestId, bytes32 _disputeId) public {
//     uint256 _bondSize = 1000;
//     uint256 _bondEscalationDeadline = block.timestamp;
//     uint256 _tyingBuffer = 1000;

//     vm.warp(_bondEscalationDeadline + _tyingBuffer + 1);

//     _setRequestData(_requestId, _bondSize, maxEscalations, _bondEscalationDeadline, _tyingBuffer, disputeWindow);
//     bondEscalationModule.forTest_setBondEscalationStatus(_requestId, IBondEscalationModule.BondEscalationStatus.Active);
//     bondEscalationModule.forTest_setEscalatedDispute(_requestId, _disputeId);

//     uint256 _numAgainstPledgers = 2;
//     uint256 _numForPledgers = _numAgainstPledgers - 1;

//     _setBondEscalation(_requestId, _numForPledgers, _numAgainstPledgers);

//     _mockAndExpect(
//       address(oracle),
//       abi.encodeCall(IOracle.updateDisputeStatus, (_disputeId, IOracle.DisputeStatus.Lost)),
//       abi.encode(true)
//     );

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(bondEscalationModule));
//     emit BondEscalationStatusUpdated(_requestId, _disputeId, IBondEscalationModule.BondEscalationStatus.DisputerLost);

//     bondEscalationModule.settleBondEscalation(_requestId);
//     // Check: is the bond escalation status properly updated?
//     assertEq(
//       uint256(bondEscalationModule.getEscalation(_requestId).status),
//       uint256(IBondEscalationModule.BondEscalationStatus.DisputerLost)
//     );
//   }
// }
