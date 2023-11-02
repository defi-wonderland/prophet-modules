// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity ^0.8.19;

// import 'forge-std/Test.sol';

// import {Helpers} from '../../../utils/Helpers.sol';

// import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
// import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
// import {IModule} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IModule.sol';

// import {
//   CircuitResolverModule,
//   ICircuitResolverModule
// } from '../../../../contracts/modules/dispute/CircuitResolverModule.sol';

// import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';

// /**
//  * @dev Harness to set an entry in the requestData mapping, without triggering setup request hooks
//  */
// contract ForTest_CircuitResolverModule is CircuitResolverModule {
//   constructor(IOracle _oracle) CircuitResolverModule(_oracle) {}

//   function forTest_setRequestData(bytes32 _requestId, bytes memory _data) public {
//     requestData[_requestId] = _data;
//   }

//   function forTest_setCorrectResponse(bytes32 _requestId, bytes memory _data) public {
//     _correctResponses[_requestId] = _data;
//   }
// }

// /**
//  * @title Bonded Dispute Module Unit tests
//  */
// contract BaseTest is Test, Helpers {
//   // The target contract
//   ForTest_CircuitResolverModule public circuitResolverModule;
//   // A mock oracle
//   IOracle public oracle;
//   // A mock accounting extension
//   IAccountingExtension public accountingExtension;
//   // Some unnoticeable dude
//   address public dude = makeAddr('dude');
//   // 100% random sequence of bytes representing request, response, or dispute id
//   bytes32 public mockId = bytes32('69');
//   // Create a new dummy dispute
//   IOracle.Dispute public mockDispute;
//   // A mock circuit verifier address
//   address public circuitVerifier;
//   // Mock addresses
//   IERC20 public _token = IERC20(makeAddr('token'));
//   address public _disputer = makeAddr('disputer');
//   address public _proposer = makeAddr('proposer');
//   bytes internal _callData = abi.encodeWithSignature('test(uint256)', 123);

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

//     accountingExtension = IAccountingExtension(makeAddr('AccountingExtension'));
//     vm.etch(address(accountingExtension), hex'069420');
//     circuitVerifier = makeAddr('CircuitVerifier');
//     vm.etch(address(circuitVerifier), hex'069420');

//     circuitResolverModule = new ForTest_CircuitResolverModule(oracle);

//     mockDispute = IOracle.Dispute({
//       createdAt: block.timestamp,
//       disputer: dude,
//       responseId: mockId,
//       proposer: dude,
//       requestId: mockId,
//       status: IOracle.DisputeStatus.Active
//     });
//   }
// }

// contract CircuitResolverModule_Unit_ModuleData is BaseTest {
//   /**
//    * @notice Test that the decodeRequestData function returns the correct values
//    */
//   function test_decodeRequestData_returnsCorrectData(
//     bytes32 _requestId,
//     address _accountingExtension,
//     address _randomToken,
//     uint256 _bondSize
//   ) public {
//     // Mock data
//     bytes memory _requestData = abi.encode(
//       ICircuitResolverModule.RequestParameters({
//         callData: _callData,
//         verifier: circuitVerifier,
//         accountingExtension: IAccountingExtension(_accountingExtension),
//         bondToken: IERC20(_randomToken),
//         bondSize: _bondSize
//       })
//     );

//     // Store the mock request
//     circuitResolverModule.forTest_setRequestData(_requestId, _requestData);

//     // Test: decode the given request data
//     ICircuitResolverModule.RequestParameters memory _params = circuitResolverModule.decodeRequestData(_requestId);

//     // Check: is the request data properly stored?
//     assertEq(_params.callData, _callData, 'Mismatch: decoded calldata');
//     assertEq(_params.verifier, circuitVerifier, 'Mismatch: decoded circuit verifier');
//     assertEq(address(_params.accountingExtension), _accountingExtension, 'Mismatch: decoded accounting extension');
//     assertEq(address(_params.bondToken), _randomToken, 'Mismatch: decoded token');
//     assertEq(_params.bondSize, _bondSize, 'Mismatch: decoded bond size');
//   }

//   /**
//    * @notice Test that the moduleName function returns the correct name
//    */
//   function test_moduleNameReturnsName() public {
//     assertEq(circuitResolverModule.moduleName(), 'CircuitResolverModule');
//   }
// }

// contract CircuitResolverModule_Unit_DisputeResponse is BaseTest {
//   /**
//    * @notice Test if dispute incorrect response returns the correct status
//    */
//   function test_disputeIncorrectResponse(bytes32 _requestId, bytes32 _responseId, uint256 _bondSize) public {
//     vm.assume(_requestId != _responseId);
//     bool _correctResponse = false;

//     // Mock request data
//     bytes memory _requestData = abi.encode(
//       ICircuitResolverModule.RequestParameters({
//         callData: _callData,
//         verifier: circuitVerifier,
//         accountingExtension: accountingExtension,
//         bondToken: IERC20(_token),
//         bondSize: _bondSize
//       })
//     );

//     // Store the mock request
//     circuitResolverModule.forTest_setRequestData(_requestId, _requestData);

//     // Create new Response memory struct with random values
//     IOracle.Response memory _mockResponse = IOracle.Response({
//       createdAt: block.timestamp,
//       proposer: _proposer,
//       requestId: _requestId,
//       disputeId: mockId,
//       response: abi.encode(true)
//     });

//     // Mock and expect the call to the oracle, getting the response
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)), abi.encode(_mockResponse));

//     // Mock and expect the call to the verifier
//     _mockAndExpect(circuitVerifier, _callData, abi.encode(_correctResponse));

//     // Test: call disputeResponse
//     vm.prank(address(oracle));
//     IOracle.Dispute memory _dispute =
//       circuitResolverModule.disputeResponse(_requestId, _responseId, _disputer, _proposer);

//     // Check: is the dispute data properly stored?
//     assertEq(_dispute.disputer, _disputer, 'Mismatch: disputer');
//     assertEq(_dispute.proposer, _proposer, 'Mismatch: proposer');
//     assertEq(_dispute.responseId, _responseId, 'Mismatch: responseId');
//     assertEq(_dispute.requestId, _requestId, 'Mismatch: requestId');
//     assertEq(uint256(_dispute.status), uint256(IOracle.DisputeStatus.Won), 'Mismatch: status');
//     assertEq(_dispute.createdAt, block.timestamp, 'Mismatch: createdAt');
//   }

//   function test_emitsEvent(bytes32 _requestId, bytes32 _responseId, uint256 _bondSize) public {
//     vm.assume(_requestId != _responseId);

//     bool _correctResponse = false;

//     // Mock request data
//     bytes memory _requestData = abi.encode(
//       ICircuitResolverModule.RequestParameters({
//         callData: _callData,
//         verifier: circuitVerifier,
//         accountingExtension: accountingExtension,
//         bondToken: IERC20(_token),
//         bondSize: _bondSize
//       })
//     );

//     // Store the mock request
//     circuitResolverModule.forTest_setRequestData(_requestId, _requestData);

//     // Create new Response memory struct with random values
//     IOracle.Response memory _mockResponse = IOracle.Response({
//       createdAt: block.timestamp,
//       proposer: _proposer,
//       requestId: _requestId,
//       disputeId: mockId,
//       response: abi.encode(true)
//     });

//     // Mock and expect the call to the oracle, getting the response
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)), abi.encode(_mockResponse));

//     // Mock and expect the call to the verifier
//     _mockAndExpect(circuitVerifier, _callData, abi.encode(_correctResponse));

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(circuitResolverModule));
//     emit ResponseDisputed(_requestId, _responseId, _disputer, _proposer);

//     vm.prank(address(oracle));
//     circuitResolverModule.disputeResponse(_requestId, _responseId, _disputer, _proposer);
//   }

//   /**
//    * @notice Test if dispute correct response returns the correct status
//    */
//   function test_disputeCorrectResponse(bytes32 _requestId, bytes32 _responseId, uint256 _bondSize) public {
//     vm.assume(_requestId != _responseId);

//     bytes memory _encodedCorrectResponse = abi.encode(true);

//     // Mock request data
//     bytes memory _requestData = abi.encode(
//       ICircuitResolverModule.RequestParameters({
//         callData: _callData,
//         verifier: circuitVerifier,
//         accountingExtension: accountingExtension,
//         bondToken: IERC20(_token),
//         bondSize: _bondSize
//       })
//     );

//     // Store the mock request
//     circuitResolverModule.forTest_setRequestData(_requestId, _requestData);

//     // Create new Response memory struct with random values
//     IOracle.Response memory _mockResponse = IOracle.Response({
//       createdAt: block.timestamp,
//       proposer: _proposer,
//       requestId: _requestId,
//       disputeId: mockId,
//       response: _encodedCorrectResponse
//     });

//     // Mock and expect the call to the oracle, getting the response
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)), abi.encode(_mockResponse));

//     // Mock and expect the call to the verifier
//     _mockAndExpect(circuitVerifier, _callData, _encodedCorrectResponse);

//     vm.prank(address(oracle));
//     IOracle.Dispute memory _dispute =
//       circuitResolverModule.disputeResponse(_requestId, _responseId, _disputer, _proposer);

//     // Check: is the dispute data properly stored?
//     assertEq(_dispute.disputer, _disputer, 'Mismatch: disputer');
//     assertEq(_dispute.proposer, _proposer, 'Mismatch: proposer');
//     assertEq(_dispute.responseId, _responseId, 'Mismatch: responseId');
//     assertEq(_dispute.requestId, _requestId, 'Mismatch: requestId');
//     assertEq(uint256(_dispute.status), uint256(IOracle.DisputeStatus.Lost), 'Mismatch: status');
//     assertEq(_dispute.createdAt, block.timestamp, 'Mismatch: createdAt');
//   }

//   /**
//    * @notice Test if dispute response reverts when called by caller who's not the oracle
//    */
//   function test_revertWrongCaller(address _randomCaller) public {
//     vm.assume(_randomCaller != address(oracle));

//     // Check: does it revert if not called by the Oracle?
//     vm.expectRevert(abi.encodeWithSelector(IModule.Module_OnlyOracle.selector));

//     vm.prank(_randomCaller);
//     circuitResolverModule.disputeResponse(mockId, mockId, dude, dude);
//   }
// }

// contract CircuitResolverModule_Unit_DisputeEscalation is BaseTest {
//   /**
//    * @notice Test if dispute escalated do nothing
//    */
//   function test_returnCorrectStatus() public {
//     // Record sstore and sload
//     vm.prank(address(oracle));
//     vm.record();
//     circuitResolverModule.disputeEscalated(mockId);
//     (bytes32[] memory _reads, bytes32[] memory _writes) = vm.accesses(address(circuitResolverModule));

//     // Check: no storage access?
//     assertEq(_reads.length, 0);
//     assertEq(_writes.length, 0);
//   }

//   /**
//    * @notice Test that escalateDispute finalizes the request if the original response is correct
//    */
//   function test_correctResponse(bytes32 _requestId, bytes32 _responseId, uint256 _bondSize) public {
//     vm.assume(_requestId != _responseId);

//     bytes memory _encodedCorrectResponse = abi.encode(true);

//     // Mock request data
//     bytes memory _requestData = abi.encode(
//       ICircuitResolverModule.RequestParameters({
//         callData: _callData,
//         verifier: circuitVerifier,
//         accountingExtension: accountingExtension,
//         bondToken: IERC20(_token),
//         bondSize: _bondSize
//       })
//     );

//     // Store the mock request
//     circuitResolverModule.forTest_setRequestData(_requestId, _requestData);

//     circuitResolverModule.forTest_setCorrectResponse(_requestId, _encodedCorrectResponse);

//     // Create new Response memory struct with random values
//     IOracle.Response memory _mockResponse = IOracle.Response({
//       createdAt: block.timestamp,
//       proposer: _proposer,
//       requestId: _requestId,
//       disputeId: mockId,
//       response: _encodedCorrectResponse
//     });

//     // Mock and expect the call to the oracle, getting the response
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)), abi.encode(_mockResponse));

//     // Mock and expect the call to the oracle, finalizing the request
//     _mockAndExpect(
//       address(oracle), abi.encodeWithSignature('finalize(bytes32,bytes32)', _requestId, _responseId), abi.encode()
//     );

//     // Populate the mock dispute with the correct values
//     mockDispute.status = IOracle.DisputeStatus.Lost;
//     mockDispute.responseId = _responseId;
//     mockDispute.requestId = _requestId;

//     vm.prank(address(oracle));
//     circuitResolverModule.onDisputeStatusChange(bytes32(0), mockDispute);
//   }

//   /**
//    * @notice Test that escalateDispute pays the disputer and proposes the new response
//    */
//   function test_incorrectResponse(bytes32 _requestId, bytes32 _responseId, uint256 _bondSize) public {
//     vm.assume(_requestId != _responseId);

//     bytes32 _correctResponseId = bytes32(uint256(mockId) + 2);
//     bytes memory _encodedCorrectResponse = abi.encode(true);

//     // Mock request data
//     bytes memory _requestData = abi.encode(
//       ICircuitResolverModule.RequestParameters({
//         callData: _callData,
//         verifier: circuitVerifier,
//         accountingExtension: accountingExtension,
//         bondToken: IERC20(_token),
//         bondSize: _bondSize
//       })
//     );

//     // Store the mock request and correct response
//     circuitResolverModule.forTest_setRequestData(_requestId, _requestData);
//     circuitResolverModule.forTest_setCorrectResponse(_requestId, _encodedCorrectResponse);

//     // Create new Response memory struct with random values
//     IOracle.Response memory _mockResponse = IOracle.Response({
//       createdAt: block.timestamp,
//       proposer: _proposer,
//       requestId: _requestId,
//       disputeId: mockId,
//       response: abi.encode(false)
//     });

//     // Mock and expect the call to the oracle, getting the response
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)), abi.encode(_mockResponse));

//     // Mock and expect the call to the accounting extension, paying the disputer
//     _mockAndExpect(
//       address(accountingExtension),
//       abi.encodeCall(accountingExtension.pay, (_requestId, _proposer, _disputer, _token, _bondSize)),
//       abi.encode()
//     );

//     // Mock and expect the call to the oracle, proposing the correct response with the disputer as the new proposer
//     _mockAndExpect(
//       address(oracle),
//       abi.encodeWithSignature(
//         'proposeResponse(address,bytes32,bytes)', _disputer, _requestId, abi.encode(_encodedCorrectResponse)
//       ),
//       abi.encode(_correctResponseId)
//     );

//     // Mock and expect the call to the oracle, finalizing the request with the correct response
//     _mockAndExpect(
//       address(oracle),
//       abi.encodeWithSignature('finalize(bytes32,bytes32)', _requestId, _correctResponseId),
//       abi.encode()
//     );

//     // Populate the mock dispute with the correct values
//     mockDispute.status = IOracle.DisputeStatus.Won;
//     mockDispute.responseId = _responseId;
//     mockDispute.requestId = _requestId;
//     mockDispute.disputer = _disputer;
//     mockDispute.proposer = _proposer;

//     vm.prank(address(oracle));
//     circuitResolverModule.onDisputeStatusChange(bytes32(0), mockDispute);
//   }
// }

// contract CircuitResolverModule_Unit_OnDisputeStatusChange is BaseTest {
//   function test_eventEmitted(bytes32 _requestId, bytes32 _responseId, uint256 _bondSize) public {
//     vm.assume(_requestId != _responseId);

//     bytes memory _encodedCorrectResponse = abi.encode(true);

//     // Mock request data
//     bytes memory _requestData = abi.encode(
//       ICircuitResolverModule.RequestParameters({
//         callData: _callData,
//         verifier: circuitVerifier,
//         accountingExtension: accountingExtension,
//         bondToken: IERC20(_token),
//         bondSize: _bondSize
//       })
//     );

//     // Store the mock request
//     circuitResolverModule.forTest_setRequestData(_requestId, _requestData);
//     circuitResolverModule.forTest_setCorrectResponse(_requestId, _encodedCorrectResponse);

//     // Create new Response memory struct with random values
//     IOracle.Response memory _mockResponse = IOracle.Response({
//       createdAt: block.timestamp,
//       proposer: _proposer,
//       requestId: _requestId,
//       disputeId: mockId,
//       response: _encodedCorrectResponse
//     });

//     // Mock and expect the call to the oracle, getting the response
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)), abi.encode(_mockResponse));

//     // Mock and expect the call to the oracle, finalizing the request
//     _mockAndExpect(
//       address(oracle), abi.encodeWithSignature('finalize(bytes32,bytes32)', _requestId, _responseId), abi.encode()
//     );

//     // Populate the mock dispute with the correct values
//     mockDispute.status = IOracle.DisputeStatus.Lost;
//     mockDispute.responseId = _responseId;
//     mockDispute.requestId = _requestId;

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(circuitResolverModule));
//     emit DisputeStatusChanged(
//       _requestId, _responseId, mockDispute.disputer, mockDispute.proposer, IOracle.DisputeStatus.Lost
//     );

//     vm.prank(address(oracle));
//     circuitResolverModule.onDisputeStatusChange(bytes32(0), mockDispute);
//   }
// }
