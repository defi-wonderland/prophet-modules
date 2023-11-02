// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity ^0.8.19;

// import 'forge-std/Test.sol';

// import {Helpers} from '../../../utils/Helpers.sol';

// import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

// import {
//   BondedResponseModule,
//   IBondedResponseModule,
//   IModule,
//   IOracle
// } from '../../../../contracts/modules/response/BondedResponseModule.sol';

// import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';

// /**
//  * @dev Harness to set an entry in the requestData mapping, without triggering setup request hooks
//  */
// contract ForTest_BondedResponseModule is BondedResponseModule {
//   constructor(IOracle _oracle) BondedResponseModule(_oracle) {}

//   function forTest_setRequestData(bytes32 _requestId, bytes memory _data) public {
//     requestData[_requestId] = _data;
//   }
// }

// /**
//  * @title Bonded Response Module Unit tests
//  */
// contract BaseTest is Test, Helpers {
//   // The target contract
//   ForTest_BondedResponseModule public bondedResponseModule;
//   // A mock oracle
//   IOracle public oracle;
//   // A mock accounting extension
//   IAccountingExtension public accounting = IAccountingExtension(makeAddr('accounting'));
//   // Base dispute window
//   uint256 internal _baseDisputeWindow = 12 hours;

//   event ResponseProposed(bytes32 indexed _requestId, IOracle.Response _response, uint256 indexed _blockNumber);
//   event RequestFinalized(bytes32 indexed _requestId, IOracle.Request _response, address indexed _finalizer);

//   /**
//    * @notice Deploy the target and mock oracle+accounting extension
//    */
//   function setUp() public {
//     oracle = IOracle(makeAddr('Oracle'));
//     vm.etch(address(oracle), hex'069420');

//     // vm.etch(address(token), hex'069420');

//     // Avoid starting at 0 for time sensitive tests
//     vm.warp(123_456);

//     bondedResponseModule = new ForTest_BondedResponseModule(oracle);
//   }
// }

// contract BondedResponseModule_Unit_ModuleData is BaseTest {
//   /**
//    * @notice Test that the moduleName function returns the correct name
//    */
//   function test_moduleNameReturnsName() public {
//     assertEq(bondedResponseModule.moduleName(), 'BondedResponseModule');
//   }

//   /**
//    * @notice Test that the decodeRequestData function returns the correct values
//    */
//   function test_decodeRequestData(
//     bytes32 _requestId,
//     uint256 _bondSize,
//     uint256 _deadline,
//     uint256 _disputeWindow,
//     IERC20 _token
//   ) public {
//     // Create and set some mock request data
//     bytes memory _data = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);
//     bondedResponseModule.forTest_setRequestData(_requestId, _data);

//     // Get the returned values
//     IBondedResponseModule.RequestParameters memory _params = bondedResponseModule.decodeRequestData(_requestId);

//     // Check: correct values returned?
//     assertEq(address(_params.accountingExtension), address(accounting), 'Mismatch: accounting extension address');
//     assertEq(address(_params.bondToken), address(_token), 'Mismatch: token address');
//     assertEq(_params.bondSize, _bondSize, 'Mismatch: bond size');
//     assertEq(_params.deadline, _deadline, 'Mismatch: deadline');
//     assertEq(_params.disputeWindow, _disputeWindow, 'Mismatch: dispute window');
//   }
// }

// contract BondedResponseModule_Unit_Propose is BaseTest {
//   /**
//    * @notice Test that the propose function is only callable by the oracle
//    */
//   function test_revertIfNotOracle(
//     bytes32 _requestId,
//     address _sender,
//     address _proposer,
//     bytes calldata _responseData
//   ) public {
//     vm.assume(_sender != address(oracle));

//     // Check: does it revert if not called by the Oracle?
//     vm.expectRevert(abi.encodeWithSelector(IModule.Module_OnlyOracle.selector));

//     vm.prank(address(_sender));
//     bondedResponseModule.propose(_requestId, _proposer, _responseData, _sender);
//   }

//   /**
//    * @notice Test that the propose function works correctly and triggers _afterPropose (which bonds)
//    */
//   function test_propose(
//     bytes32 _requestId,
//     uint256 _bondSize,
//     uint256 _deadline,
//     uint256 _disputeWindow,
//     bytes calldata _responseData,
//     address _sender,
//     IERC20 _token,
//     address _proposer
//   ) public {
//     _deadline = bound(_deadline, block.timestamp + 1, type(uint248).max);
//     _disputeWindow = bound(_disputeWindow, 61, 365 days);
//     _bondSize = bound(_bondSize, 0, type(uint248).max);

//     // Create and set some mock request data
//     bytes memory _data = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);
//     bondedResponseModule.forTest_setRequestData(_requestId, _data);

//     // Mock and expect IOracle.getResponseIds to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponseIds, _requestId), abi.encode(new bytes32[](0)));

//     // Mock and expect IAccountingExtension.bond to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeWithSignature(
//         'bond(address,bytes32,address,uint256,address)', _proposer, _requestId, _token, _bondSize, _sender
//       ),
//       abi.encode()
//     );

//     vm.prank(address(oracle));
//     IOracle.Response memory _responseReturned =
//       bondedResponseModule.propose(_requestId, _proposer, _responseData, _sender);

//     IOracle.Response memory _responseExpected = IOracle.Response({
//       createdAt: block.timestamp,
//       requestId: _requestId,
//       disputeId: bytes32(''),
//       proposer: _proposer,
//       response: _responseData
//     });

//     // Check: correct response struct returned?
//     assertEq(_responseReturned.requestId, _responseExpected.requestId, 'Mismatch: request ID');
//     assertEq(_responseReturned.disputeId, _responseExpected.disputeId, 'Mismatch: dispute ID');
//     assertEq(_responseReturned.proposer, _responseExpected.proposer, 'Mismatch: proposer address');
//     assertEq(_responseReturned.response, _responseExpected.response, 'Mismatch: response object');
//   }

//   function test_emitsEvent(
//     bytes32 _requestId,
//     uint256 _bondSize,
//     uint256 _deadline,
//     uint256 _disputeWindow,
//     bytes calldata _responseData,
//     address _sender,
//     IERC20 _token,
//     address _proposer
//   ) public {
//     _deadline = bound(_deadline, block.timestamp + 1, type(uint248).max);
//     _disputeWindow = bound(_disputeWindow, 61, 365 days);

//     // Create and set some mock request data
//     bytes memory _data = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);
//     bondedResponseModule.forTest_setRequestData(_requestId, _data);

//     // Mock and expect IOracle.getResponseIds to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponseIds, _requestId), abi.encode(new bytes32[](0)));

//     // Mock and expect IOracle.getResponseIds to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeWithSignature(
//         'bond(address,bytes32,address,uint256,address)', _proposer, _requestId, _token, _bondSize, _sender
//       ),
//       abi.encode()
//     );

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(bondedResponseModule));
//     emit ResponseProposed(_requestId, _proposer, _responseData);

//     vm.prank(address(oracle));
//     bondedResponseModule.propose(_requestId, _proposer, _responseData, _sender);
//   }
// }

// contract BondedResponseModule_Unit_FinalizeRequest is BaseTest {
//   /**
//    * @notice Test that the propose function is only callable by the oracle
//    */
//   function test_calls(
//     bytes32 _requestId,
//     uint256 _bondSize,
//     uint256 _deadline,
//     uint256 _disputeWindow,
//     IERC20 _token,
//     address _proposer
//   ) public {
//     _deadline = bound(_deadline, block.timestamp + 1, type(uint248).max);
//     _disputeWindow = bound(_disputeWindow, 61, 365 days);

//     // Check revert if deadline has not passed
//     bytes memory _data = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);
//     bondedResponseModule.forTest_setRequestData(_requestId, _data);

//     // Mock and expect IOracle.allowedModule to be called
//     _mockAndExpect(
//       address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, address(this))), abi.encode(false)
//     );

//     // Check: does it revert if it's too early to finalize?
//     vm.expectRevert(IBondedResponseModule.BondedResponseModule_TooEarlyToFinalize.selector);

//     vm.prank(address(oracle));
//     bondedResponseModule.finalizeRequest(_requestId, address(this));

//     // Check correct calls are made if deadline has passed
//     _deadline = block.timestamp;

//     _data = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);
//     bondedResponseModule.forTest_setRequestData(_requestId, _data);

//     IOracle.Response memory _mockResponse = IOracle.Response({
//       createdAt: block.timestamp,
//       requestId: _requestId,
//       disputeId: bytes32(''),
//       proposer: _proposer,
//       response: bytes('bleh')
//     });

//     // Mock and expect IOracle.getFinalizedResponse to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getFinalizedResponse, _requestId), abi.encode(_mockResponse));

//     // Mock and expect IAccountingExtension.release to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(IAccountingExtension.release, (_proposer, _requestId, _token, _bondSize)),
//       abi.encode(true)
//     );

//     vm.warp(block.timestamp + _disputeWindow);

//     vm.prank(address(oracle));
//     bondedResponseModule.finalizeRequest(_requestId, address(this));
//   }

//   function test_emitsEvent(
//     bytes32 _requestId,
//     uint256 _bondSize,
//     uint256 _deadline,
//     uint256 _disputeWindow,
//     IERC20 _token,
//     address _proposer
//   ) public {
//     _deadline = bound(_deadline, block.timestamp + 1, type(uint248).max);
//     _disputeWindow = bound(_disputeWindow, 61, 365 days);

//     // Check revert if deadline has not passed
//     bytes memory _data = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);
//     bondedResponseModule.forTest_setRequestData(_requestId, _data);

//     // Mock and expect IOracle.allowedModule to be called
//     _mockAndExpect(
//       address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, address(this))), abi.encode(false)
//     );

//     // Check correct calls are made if deadline has passed
//     _deadline = block.timestamp;

//     _data = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);
//     bondedResponseModule.forTest_setRequestData(_requestId, _data);

//     IOracle.Response memory _mockResponse = IOracle.Response({
//       createdAt: block.timestamp,
//       requestId: _requestId,
//       disputeId: bytes32(''),
//       proposer: _proposer,
//       response: bytes('bleh')
//     });

//     // Mock and expect IOracle.getFinalizedResponse to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getFinalizedResponse, _requestId), abi.encode(_mockResponse));

//     // Mock and expect IAccountingExtension.release to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(IAccountingExtension.release, (_proposer, _requestId, _token, _bondSize)),
//       abi.encode(true)
//     );

//     // Check: is event emitted?
//     vm.expectEmit(true, true, true, true, address(bondedResponseModule));
//     emit RequestFinalized(_requestId, address(this));

//     vm.warp(block.timestamp + _disputeWindow);

//     vm.prank(address(oracle));
//     bondedResponseModule.finalizeRequest(_requestId, address(this));
//   }

//   /**
//    * @notice Test that the finalize function can be called by an allowed module before the time window.
//    */
//   function test_earlyByModule(
//     bytes32 _requestId,
//     uint256 _bondSize,
//     uint256 _deadline,
//     IERC20 _token,
//     address _proposer
//   ) public {
//     _deadline = bound(_deadline, block.timestamp + 1, type(uint248).max);

//     address _allowedModule = makeAddr('allowed module');
//     bytes memory _data = abi.encode(accounting, _token, _bondSize, _deadline, _baseDisputeWindow);
//     bondedResponseModule.forTest_setRequestData(_requestId, _data);

//     // Mock and expect IOracle.allowedModule to be called
//     _mockAndExpect(
//       address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _allowedModule)), abi.encode(true)
//     );

//     IOracle.Response memory _mockResponse = IOracle.Response({
//       createdAt: block.timestamp,
//       requestId: _requestId,
//       disputeId: bytes32(''),
//       proposer: _proposer,
//       response: bytes('bleh')
//     });

//     // Mock and expect IOracle.getFinalizedResponse to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getFinalizedResponse, _requestId), abi.encode(_mockResponse));

//     // Mock and expect IAccountingExtension.release to be called
//     _mockAndExpect(
//       address(accounting),
//       abi.encodeCall(IAccountingExtension.release, (_proposer, _requestId, _token, _bondSize)),
//       abi.encode(true)
//     );

//     vm.prank(address(oracle));
//     bondedResponseModule.finalizeRequest(_requestId, _allowedModule);
//   }

//   /**
//    * @notice Test that the finalizing a request during a response dispute window will revert.
//    */
//   function test_revertDuringDisputeWindow(
//     bytes32 _requestId,
//     uint256 _bondSize,
//     uint256 _deadline,
//     IERC20 _token,
//     address _proposer
//   ) public {
//     _deadline = bound(_deadline, block.timestamp + 1, type(uint248).max);

//     address _finalizer = makeAddr('finalizer');
//     bytes memory _data = abi.encode(accounting, _token, _bondSize, _deadline, _baseDisputeWindow);
//     bondedResponseModule.forTest_setRequestData(_requestId, _data);

//     // Mock and expect IOracle.allowedModule to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _finalizer)), abi.encode(false));

//     IOracle.Response memory _mockResponse = IOracle.Response({
//       createdAt: _deadline - 1,
//       requestId: _requestId,
//       disputeId: bytes32(''),
//       proposer: _proposer,
//       response: bytes('bleh')
//     });

//     // Mock and expect IOracle.getFinalizedResponse to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getFinalizedResponse, _requestId), abi.encode(_mockResponse));

//     vm.expectRevert(IBondedResponseModule.BondedResponseModule_TooEarlyToFinalize.selector);

//     vm.warp(_deadline + 1);
//     vm.prank(address(oracle));
//     bondedResponseModule.finalizeRequest(_requestId, _finalizer);
//   }
// }
