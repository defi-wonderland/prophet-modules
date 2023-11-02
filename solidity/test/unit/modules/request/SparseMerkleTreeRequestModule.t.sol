// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity ^0.8.19;

// import 'forge-std/Test.sol';

// import {Helpers} from '../../../utils/Helpers.sol';

// import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
// import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
// import {IModule} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IModule.sol';

// import {
//   SparseMerkleTreeRequestModule,
//   ISparseMerkleTreeRequestModule
// } from '../../../../contracts/modules/request/SparseMerkleTreeRequestModule.sol';

// import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';
// import {ITreeVerifier} from '../../../../interfaces/ITreeVerifier.sol';

// /**
//  * @dev Harness to set an entry in the requestData mapping, without triggering setup request hooks
//  */

// contract ForTest_SparseMerkleTreeRequestModule is SparseMerkleTreeRequestModule {
//   constructor(IOracle _oracle) SparseMerkleTreeRequestModule(_oracle) {}

//   function forTest_setRequestData(bytes32 _requestId, bytes memory _data) public {
//     requestData[_requestId] = _data;
//   }
// }

// /**
//  * @title Sparse Merkle Tree Request Module Unit tests
//  */
// contract BaseTest is Test, Helpers {
//   // The target contract
//   ForTest_SparseMerkleTreeRequestModule public sparseMerkleTreeRequestModule;
//   // A mock oracle
//   IOracle public oracle;
//   // A mock accounting extension
//   IAccountingExtension public accounting;
//   // A mock tree verifier
//   ITreeVerifier public treeVerifier;
//   // Mock data for the request
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

//   event RequestFinalized(bytes32 indexed _requestId, address _finalizer);

//   /**
//    * @notice Deploy the target and mock oracle+accounting extension
//    */
//   function setUp() public {
//     oracle = IOracle(makeAddr('Oracle'));
//     vm.etch(address(oracle), hex'069420');

//     accounting = IAccountingExtension(makeAddr('AccountingExtension'));
//     vm.etch(address(accounting), hex'069420');
//     treeVerifier = ITreeVerifier(makeAddr('TreeVerifier'));
//     vm.etch(address(accounting), hex'069420');

//     sparseMerkleTreeRequestModule = new ForTest_SparseMerkleTreeRequestModule(oracle);
//   }
// }

// contract SparseMerkleTreeRequestModule_Unit_ModuleData is BaseTest {
//   /**
//    * @notice Test that the moduleName function returns the correct name
//    */
//   function test_moduleNameReturnsName() public {
//     assertEq(sparseMerkleTreeRequestModule.moduleName(), 'SparseMerkleTreeRequestModule', 'Wrong module name');
//   }

//   /**
//    * @notice Test that the decodeRequestData function returns the correct values
//    */
//   function test_decodeRequestData(
//     bytes32 _requestId,
//     IERC20 _paymentToken,
//     uint256 _paymentAmount,
//     IAccountingExtension _accounting,
//     ITreeVerifier _treeVerifier
//   ) public {
//     bytes memory _requestData = abi.encode(
//       ISparseMerkleTreeRequestModule.RequestParameters({
//         treeData: _treeData,
//         leavesToInsert: _leavesToInsert,
//         treeVerifier: _treeVerifier,
//         accountingExtension: _accounting,
//         paymentToken: _paymentToken,
//         paymentAmount: _paymentAmount
//       })
//     );

//     // Set the request data
//     sparseMerkleTreeRequestModule.forTest_setRequestData(_requestId, _requestData);

//     // Decode the given request data
//     ISparseMerkleTreeRequestModule.RequestParameters memory _params =
//       sparseMerkleTreeRequestModule.decodeRequestData(_requestId);

//     (bytes32[32] memory _decodedTreeBranches, uint256 _decodedTreeCount) =
//       abi.decode(_params.treeData, (bytes32[32], uint256));

//     // Check: decoded values match original values?
//     for (uint256 _i = 0; _i < _treeBranches.length; _i++) {
//       assertEq(_decodedTreeBranches[_i], _treeBranches[_i], 'Mismatch: decoded tree branch');
//     }
//     for (uint256 _i = 0; _i < _leavesToInsert.length; _i++) {
//       assertEq(_params.leavesToInsert[_i], _leavesToInsert[_i], 'Mismatch: decoded leave to insert');
//     }
//     assertEq(_decodedTreeCount, _treeCount, 'Mismatch: decoded tree count');
//     assertEq(address(_params.treeVerifier), address(_treeVerifier), 'Mismatch: decoded tree verifier');
//     assertEq(address(_params.accountingExtension), address(_accounting), 'Mismatch: decoded accounting extension');
//     assertEq(address(_params.paymentToken), address(_paymentToken), 'Mismatch: decoded payment token');
//     assertEq(_params.paymentAmount, _paymentAmount, 'Mismatch: decoded payment amount');
//   }
// }

// contract SparseMerkleTreeRequestModule_Unit_Setup is BaseTest {
//   /**
//    * @notice Test that the afterSetupRequest hook:
//    *          - decodes the request data
//    *          - gets the request from the oracle
//    *          - calls the bond function on the accounting extension
//    */
//   function test_afterSetupRequestTriggered(
//     bytes32 _requestId,
//     address _requester,
//     IERC20 _paymentToken,
//     uint256 _paymentAmount,
//     IAccountingExtension _accounting,
//     ITreeVerifier _treeVerifier
//   ) public assumeFuzzable(address(_accounting)) {
//     bytes memory _requestData = abi.encode(
//       ISparseMerkleTreeRequestModule.RequestParameters({
//         treeData: _treeData,
//         leavesToInsert: _leavesToInsert,
//         treeVerifier: _treeVerifier,
//         accountingExtension: _accounting,
//         paymentToken: _paymentToken,
//         paymentAmount: _paymentAmount
//       })
//     );

//     IOracle.Request memory _fullRequest;
//     _fullRequest.requester = _requester;

//     // Mock and expect IOracle.getRequest to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getRequest, (_requestId)), abi.encode(_fullRequest));

//     // Mock and expect IAccountingExtension.bond to be called
//     _mockAndExpect(
//       address(_accounting),
//       abi.encodeWithSignature(
//         'bond(address,bytes32,address,uint256)', _requester, _requestId, _paymentToken, _paymentAmount
//       ),
//       abi.encode(true)
//     );

//     vm.prank(address(oracle));
//     sparseMerkleTreeRequestModule.setupRequest(_requestId, _requestData);

//     // Check: request data was set?
//     assertEq(sparseMerkleTreeRequestModule.requestData(_requestId), _requestData, 'Mismatch: Request data');
//   }
// }

// contract SparseMerkleTreeRequestModule_Unit_FinalizeRequest is BaseTest {
//   /**
//    * @notice Test that finalizeRequest calls:
//    *          - oracle get request
//    *          - oracle get response
//    *          - accounting extension pay
//    *          - accounting extension release
//    */
//   function test_makesCalls(
//     bytes32 _requestId,
//     address _requester,
//     address _proposer,
//     IERC20 _paymentToken,
//     uint256 _paymentAmount,
//     IAccountingExtension _accounting,
//     ITreeVerifier _treeVerifier
//   ) public assumeFuzzable(address(_accounting)) {
//     // Use the correct accounting parameters
//     bytes memory _requestData = abi.encode(
//       ISparseMerkleTreeRequestModule.RequestParameters({
//         treeData: _treeData,
//         leavesToInsert: _leavesToInsert,
//         treeVerifier: _treeVerifier,
//         accountingExtension: _accounting,
//         paymentToken: _paymentToken,
//         paymentAmount: _paymentAmount
//       })
//     );

//     IOracle.Request memory _fullRequest;
//     _fullRequest.requester = _requester;

//     IOracle.Response memory _fullResponse;
//     _fullResponse.proposer = _proposer;
//     _fullResponse.createdAt = block.timestamp;

//     // Set the request data
//     sparseMerkleTreeRequestModule.forTest_setRequestData(_requestId, _requestData);

//     // Mock and expect IOracle.getRequest to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getRequest, (_requestId)), abi.encode(_fullRequest));

//     // Mock and expect IOracle.getFinalizedResponse to be called
//     vm.mockCall(address(oracle), abi.encodeCall(IOracle.getFinalizedResponse, (_requestId)), abi.encode(_fullResponse));

//     // Mock and expect IAccountingExtension.pay to be called
//     vm.mockCall(
//       address(_accounting),
//       abi.encodeCall(IAccountingExtension.pay, (_requestId, _requester, _proposer, _paymentToken, _paymentAmount)),
//       abi.encode()
//     );

//     vm.startPrank(address(oracle));
//     sparseMerkleTreeRequestModule.finalizeRequest(_requestId, address(oracle));

//     // Test the release flow
//     _fullResponse.createdAt = 0;

//     // Update mock call to return the response with createdAt = 0
//     _mockAndExpect(
//       address(oracle), abi.encodeCall(IOracle.getFinalizedResponse, (_requestId)), abi.encode(_fullResponse)
//     );

//     // Mock and expect IAccountingExtension.release to be called
//     _mockAndExpect(
//       address(_accounting),
//       abi.encodeCall(IAccountingExtension.release, (_requester, _requestId, _paymentToken, _paymentAmount)),
//       abi.encode(true)
//     );

//     sparseMerkleTreeRequestModule.finalizeRequest(_requestId, address(this));
//   }

//   function test_emitsEvent(
//     bytes32 _requestId,
//     address _requester,
//     address _proposer,
//     IERC20 _paymentToken,
//     uint256 _paymentAmount,
//     IAccountingExtension _accounting,
//     ITreeVerifier _treeVerifier
//   ) public assumeFuzzable(address(_accounting)) {
//     // Use the correct accounting parameters
//     bytes memory _requestData = abi.encode(
//       ISparseMerkleTreeRequestModule.RequestParameters({
//         treeData: _treeData,
//         leavesToInsert: _leavesToInsert,
//         treeVerifier: _treeVerifier,
//         accountingExtension: _accounting,
//         paymentToken: _paymentToken,
//         paymentAmount: _paymentAmount
//       })
//     );

//     IOracle.Request memory _fullRequest;
//     _fullRequest.requester = _requester;

//     IOracle.Response memory _fullResponse;
//     _fullResponse.proposer = _proposer;
//     _fullResponse.createdAt = block.timestamp;

//     // Set the request data
//     sparseMerkleTreeRequestModule.forTest_setRequestData(_requestId, _requestData);

//     // Mock and expect IOracle.getRequest to be called
//     _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getRequest, (_requestId)), abi.encode(_fullRequest));

//     // Mock and expect IOracle.getFinalizedResponse to be called
//     _mockAndExpect(
//       address(oracle), abi.encodeCall(IOracle.getFinalizedResponse, (_requestId)), abi.encode(_fullResponse)
//     );

//     // Mock and expect IOracle.getRequest to be called
//     _mockAndExpect(
//       address(_accounting),
//       abi.encodeCall(IAccountingExtension.pay, (_requestId, _requester, _proposer, _paymentToken, _paymentAmount)),
//       abi.encode()
//     );

//     vm.startPrank(address(oracle));
//     sparseMerkleTreeRequestModule.finalizeRequest(_requestId, address(oracle));

//     // Test the release flow
//     _fullResponse.createdAt = 0;

//     // Update mock call to return the response with createdAt = 0
//     _mockAndExpect(
//       address(oracle), abi.encodeCall(IOracle.getFinalizedResponse, (_requestId)), abi.encode(_fullResponse)
//     );

//     // Mock and expect IOracle.getRequest to be called
//     _mockAndExpect(
//       address(_accounting),
//       abi.encodeCall(IAccountingExtension.release, (_requester, _requestId, _paymentToken, _paymentAmount)),
//       abi.encode(true)
//     );

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(sparseMerkleTreeRequestModule));
//     emit RequestFinalized(_requestId, address(this));

//     sparseMerkleTreeRequestModule.finalizeRequest(_requestId, address(this));
//   }

//   /**
//    * @notice Test that the finalizeRequest reverts if caller is not the oracle
//    */
//   function test_revertsIfWrongCaller(bytes32 _requestId, address _caller) public {
//     vm.assume(_caller != address(oracle));

//     // Check: does it revert if not called by the Oracle?
//     vm.expectRevert(abi.encodeWithSelector(IModule.Module_OnlyOracle.selector));

//     vm.prank(_caller);
//     sparseMerkleTreeRequestModule.finalizeRequest(_requestId, address(_caller));
//   }
// }
