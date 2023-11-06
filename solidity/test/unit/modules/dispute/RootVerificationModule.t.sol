// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity ^0.8.19;

// import 'forge-std/Test.sol';

// import {Helpers} from '../../../utils/Helpers.sol';

// import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
// import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
// import {IModule} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IModule.sol';

// import {
//   RootVerificationModule,
//   IRootVerificationModule
// } from '../../../../contracts/modules/dispute/RootVerificationModule.sol';

// import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';
// import {ITreeVerifier} from '../../../../interfaces/ITreeVerifier.sol';

// /**
//  * @dev Harness to set an entry in the requestData mapping, without triggering setup request hooks
//  */
// contract ForTest_RootVerificationModule is RootVerificationModule {
//   constructor(IOracle _oracle) RootVerificationModule(_oracle) {}

//   function forTest_setRequestData(bytes32 _requestId, bytes memory _data) public {
//     requestData[_requestId] = _data;
//   }
// }

// /**
//  * @title Root Verification Module Unit tests
//  */
// contract BaseTest is Test, Helpers {
//   // The target contract
//   ForTest_RootVerificationModule public rootVerificationModule;
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
//   // A mock tree verifier
//   ITreeVerifier public treeVerifier;
//   // Mock addresses
//   IERC20 public _token = IERC20(makeAddr('token'));
//   address public _disputer = makeAddr('disputer');
//   address public _proposer = makeAddr('proposer');

//   // Mock request data
//   bytes32[32] internal _treeBranches = [
//     bytes32('branch1'),
//     bytes32('branch2'),
//     bytes32('branch3'),
//     bytes32('branch4'),
//     bytes32('branch5'),
//     bytes32('branch6'),
//     bytes32('branch7'),
//     bytes32('branch8'),
//     bytes32('branch9'),
//     bytes32('branch10'),
//     bytes32('branch11'),
//     bytes32('branch12'),
//     bytes32('branch13'),
//     bytes32('branch14'),
//     bytes32('branch15'),
//     bytes32('branch16'),
//     bytes32('branch17'),
//     bytes32('branch18'),
//     bytes32('branch19'),
//     bytes32('branch20'),
//     bytes32('branch21'),
//     bytes32('branch22'),
//     bytes32('branch23'),
//     bytes32('branch24'),
//     bytes32('branch25'),
//     bytes32('branch26'),
//     bytes32('branch27'),
//     bytes32('branch28'),
//     bytes32('branch29'),
//     bytes32('branch30'),
//     bytes32('branch31'),
//     bytes32('branch32')
//   ];
//   uint256 internal _treeCount = 1;
//   bytes internal _treeData = abi.encode(_treeBranches, _treeCount);
//   bytes32[] internal _leavesToInsert = [bytes32('leave1'), bytes32('leave2')];

//   event ResponseDisputed(bytes32 indexed _requestId, bytes32 _responseId, address _disputer, address _proposer);

//   /**
//    * @notice Deploy the target and mock oracle+accounting extension
//    */
//   function setUp() public {
//     oracle = IOracle(makeAddr('Oracle'));
//     vm.etch(address(oracle), hex'069420');

//     accountingExtension = IAccountingExtension(makeAddr('AccountingExtension'));
//     vm.etch(address(accountingExtension), hex'069420');
//     treeVerifier = ITreeVerifier(makeAddr('TreeVerifier'));
//     vm.etch(address(treeVerifier), hex'069420');

//     rootVerificationModule = new ForTest_RootVerificationModule(oracle);

//     mockDispute = IOracle.Dispute({
//       disputer: dude,
//       responseId: mockId,
//       proposer: dude,
//       requestId: mockId,

//     });
//   }
// }

// contract RootVerificationModule_Unit_ModuleData is BaseTest {
//   /**
//    * @notice Test that the moduleName function returns the correct name
//    */
//   function test_moduleNameReturnsName() public {
//     assertEq(rootVerificationModule.moduleName(), 'RootVerificationModule');
//   }

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
//       IRootVerificationModule.RequestParameters({
//         treeData: _treeData,
//         leavesToInsert: _leavesToInsert,
//         treeVerifier: treeVerifier,
//         accountingExtension: IAccountingExtension(_accountingExtension),
//         bondToken: IERC20(_randomToken),
//         bondSize: _bondSize
//       })
//     );

//     // Store the mock request
//     rootVerificationModule.forTest_setRequestData(_requestId, _requestData);

//     IRootVerificationModule.RequestParameters memory _params = rootVerificationModule.decodeRequestData(_requestId);

//     bytes32[32] memory _treeBranchesStored;
//     uint256 _treeCountStored;
//     (_treeBranchesStored, _treeCountStored) = abi.decode(_params.treeData, (bytes32[32], uint256));

//     // Check: is the request data properly stored?
//     for (uint256 _i = 0; _i < _treeBranches.length; _i++) {
//       assertEq(_treeBranchesStored[_i], _treeBranches[_i], 'Mismatch: decoded tree branch');
//     }
//     for (uint256 _i = 0; _i < _leavesToInsert.length; _i++) {
//       assertEq(_params.leavesToInsert[_i], _leavesToInsert[_i], 'Mismatch: decoded leave to insert');
//     }
//     assertEq(_treeCountStored, _treeCount, 'Mismatch: decoded tree count');
//     assertEq(address(_params.treeVerifier), address(treeVerifier), 'Mismatch: decoded tree verifier');
//     assertEq(address(_params.accountingExtension), _accountingExtension, 'Mismatch: decoded accounting extension');
//     assertEq(address(_params.bondToken), _randomToken, 'Mismatch: decoded token');
//     assertEq(_params.bondSize, _bondSize, 'Mismatch: decoded bond size');
//   }
// }

// contract RootVerificationModule_Unit_DisputeResponse is BaseTest {
//   /**
//    * @notice Test if dispute incorrect response returns the correct status
//    */
//   function test_disputeIncorrectResponse(bytes32 _requestId, bytes32 _responseId, uint256 _bondSize) public {
//     vm.assume(_requestId != _responseId);

//     // Mock request data
//     bytes memory _requestData = abi.encode(
//       IRootVerificationModule.RequestParameters({
//         treeData: _treeData,
//         leavesToInsert: _leavesToInsert,
//         treeVerifier: treeVerifier,
//         accountingExtension: accountingExtension,
//         bondToken: _token,
//         bondSize: _bondSize
//       })
//     );

//     // Store the mock request
//     rootVerificationModule.forTest_setRequestData(_requestId, _requestData);

//     // Create new Response memory struct with random values
//     IOracle.Response memory _mockResponse = IOracle.Response({
//       createdAt: block.timestamp,
//       proposer: _proposer,
//       requestId: _requestId,
//       disputeId: mockId,
//       response: abi.encode(bytes32('randomRoot'))
//     });

//     // Mock and expect the call to the oracle, getting the response
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)), abi.encode(_mockResponse));

//     // Mock and expect the call to the tree verifier, calculating the root
//     _mockAndExpect(
//       address(treeVerifier),
//       abi.encodeCall(ITreeVerifier.calculateRoot, (_treeData, _leavesToInsert)),
//       abi.encode(bytes32('randomRoot2'))
//     );

//     vm.prank(address(oracle));
//     IOracle.Dispute memory _dispute =
//       rootVerificationModule.disputeResponse(_requestId, _responseId, _disputer, _proposer);

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

//     // Mock request data
//     bytes memory _requestData = abi.encode(
//       IRootVerificationModule.RequestParameters({
//         treeData: _treeData,
//         leavesToInsert: _leavesToInsert,
//         treeVerifier: treeVerifier,
//         accountingExtension: accountingExtension,
//         bondToken: _token,
//         bondSize: _bondSize
//       })
//     );

//     // Store the mock request
//     rootVerificationModule.forTest_setRequestData(_requestId, _requestData);

//     // Create new Response memory struct with random values
//     IOracle.Response memory _mockResponse = IOracle.Response({
//       createdAt: block.timestamp,
//       proposer: _proposer,
//       requestId: _requestId,
//       disputeId: mockId,
//       response: abi.encode(bytes32('randomRoot'))
//     });

//     // Mock and expect the call to the oracle, getting the response
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)), abi.encode(_mockResponse));

//     // Mock and expect the call to the tree verifier, calculating the root
//     _mockAndExpect(
//       address(treeVerifier),
//       abi.encodeCall(ITreeVerifier.calculateRoot, (_treeData, _leavesToInsert)),
//       abi.encode(bytes32('randomRoot2'))
//     );

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(rootVerificationModule));
//     emit ResponseDisputed({_requestId: _dispute.requestId, _responseId: _dispute.responseId, _dispute: _dispute, blockNumber: block.number});

//     vm.prank(address(oracle));
//     rootVerificationModule.disputeResponse(_requestId, _responseId, _disputer, _proposer);
//   }

//   /**
//    * @notice Test if dispute correct response returns the correct status
//    */
//   function test_disputeCorrectResponse(bytes32 _requestId, bytes32 _responseId, uint256 _bondSize) public {
//     vm.assume(_requestId != _responseId);

//     bytes memory _encodedCorrectRoot = abi.encode(bytes32('randomRoot'));

//     // Mock request data
//     bytes memory _requestData = abi.encode(
//       IRootVerificationModule.RequestParameters({
//         treeData: _treeData,
//         leavesToInsert: _leavesToInsert,
//         treeVerifier: treeVerifier,
//         accountingExtension: accountingExtension,
//         bondToken: _token,
//         bondSize: _bondSize
//       })
//     );

//     // Store the mock request
//     rootVerificationModule.forTest_setRequestData(_requestId, _requestData);

//     // Create new Response memory struct with random values
//     IOracle.Response memory _mockResponse = IOracle.Response({
//       createdAt: block.timestamp,
//       proposer: _proposer,
//       requestId: _requestId,
//       disputeId: mockId,
//       response: _encodedCorrectRoot
//     });

//     // Mock and expect the call to the oracle, getting the response
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponse, (_responseId)), abi.encode(_mockResponse));

//     // Mock and expect the call to the tree verifier, calculating the root
//     _mockAndExpect(
//       address(treeVerifier),
//       abi.encodeCall(ITreeVerifier.calculateRoot, (_treeData, _leavesToInsert)),
//       _encodedCorrectRoot
//     );

//     vm.prank(address(oracle));
//     IOracle.Dispute memory _dispute =
//       rootVerificationModule.disputeResponse(_requestId, _responseId, _disputer, _proposer);

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

//     // Check: revert if not called by the Oracle?
//     vm.expectRevert(abi.encodeWithSelector(IModule.Module_OnlyOracle.selector));

//     vm.prank(_randomCaller);
//     rootVerificationModule.disputeResponse(mockId, mockId, dude, dude);
//   }
// }
