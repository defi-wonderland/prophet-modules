// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity ^0.8.19;

// import 'forge-std/Test.sol';

// import {Helpers} from '../../../utils/Helpers.sol';

// import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
// import {IModule} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IModule.sol';

// import {
//   MultipleCallbacksModule,
//   IMultipleCallbacksModule
// } from '../../../../contracts/modules/finality/MultipleCallbacksModule.sol';

// /**
//  * @dev Harness to set an entry in the requestData mapping, without triggering setup request hooks
//  */
// contract ForTest_MultipleCallbacksModule is MultipleCallbacksModule {
//   constructor(IOracle _oracle) MultipleCallbacksModule(_oracle) {}

//   function forTest_setRequestData(bytes32 _requestId, address[] calldata _targets, bytes[] calldata _data) public {
//     requestData[_requestId] = abi.encode(IMultipleCallbacksModule.RequestParameters({targets: _targets, data: _data}));
//   }
// }

// contract BaseTest is Test, Helpers {
//   // The target contract
//   ForTest_MultipleCallbacksModule public multipleCallbackModule;
//   // A mock oracle
//   IOracle public oracle;

//   event Callback(bytes32 indexed _request, address indexed _target, bytes _data);
//   event RequestFinalized(bytes32 indexed _requestId, address _finalizer);

//   /**
//    * @notice Deploy the target and mock oracle+accounting extension
//    */
//   function setUp() public {
//     oracle = IOracle(makeAddr('Oracle'));
//     vm.etch(address(oracle), hex'069420');

//     multipleCallbackModule = new ForTest_MultipleCallbacksModule(oracle);
//   }
// }

// /**
//  * @title MultipleCallback Module Unit tests
//  */
// contract MultipleCallbacksModule_Unit_ModuleData is BaseTest {
//   /**
//    * @notice Test that the moduleName function returns the correct name
//    */
//   function test_moduleNameReturnsName() public {
//     assertEq(multipleCallbackModule.moduleName(), 'MultipleCallbacksModule');
//   }
// }

// contract MultipleCallbacksModule_Unit_FinalizeRequests is BaseTest {
//   /**
//    * @notice Test that finalizeRequests calls the _target.callback with the correct data
//    */
//   function test_finalizeRequest(bytes32 _requestId, address[1] calldata _targets, bytes[1] calldata __data) public {
//     address _target = _targets[0];
//     bytes calldata _data = __data[0];

//     assumeNotPrecompile(_target);
//     vm.assume(_target != address(vm));

//     // Create and set some mock request data
//     address[] memory _targetParams = new address[](1);
//     _targetParams[0] = _targets[0];
//     bytes[] memory _dataParams = new bytes[](1);
//     _dataParams[0] = __data[0];
//     multipleCallbackModule.forTest_setRequestData(_requestId, _targetParams, _dataParams);

//     _mockAndExpect(_target, _data, abi.encode());

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(multipleCallbackModule));
//     emit Callback(_requestId, _target, _data);

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(multipleCallbackModule));
//     emit RequestFinalized(_requestId, address(oracle));

//     vm.prank(address(oracle));
//     multipleCallbackModule.finalizeRequest(_requestId, address(oracle));
//   }

//   /**
//    * @notice Test that the finalizeRequests reverts if caller is not the oracle
//    */
//   function test_revertsIfWrongCaller(bytes32 _requestId, address _caller) public {
//     vm.assume(_caller != address(oracle));

//     // Check: does it revert if not called by the Oracle?
//     vm.expectRevert(IModule.Module_OnlyOracle.selector);
//     vm.prank(_caller);
//     multipleCallbackModule.finalizeRequest(_requestId, address(_caller));
//   }

//   function test_revertIfInvalidParameters(bytes32 _requestId, address[] memory _targets, bytes[] memory _data) public {
//     vm.assume(_targets.length != _data.length);

//     bytes memory _requestData = abi.encode(IMultipleCallbacksModule.RequestParameters({targets: _targets, data: _data}));

//     // Check: does it revert if arrays length mismatch?
//     vm.expectRevert(IMultipleCallbacksModule.MultipleCallbackModule_InvalidParameters.selector);
//     vm.prank(address(oracle));
//     multipleCallbackModule.setupRequest(_requestId, _requestData);
//   }
// }

// contract MultipleCallbacksModule_Unit_Setup is BaseTest {
//   function test_revertsIfInvalidTarget(bytes32 _requestId, address[] memory _targets, bytes memory _data) public {
//     vm.assume(_targets.length > 1);

//     // Hardcoding data (as it is not the case tested) to avoid vm.assume issues
//     bytes[] memory _targetData = new bytes[](_targets.length);
//     for (uint256 _i = 0; _i < _targets.length; _i++) {
//       _targetData[_i] = abi.encodeWithSelector(bytes4(keccak256('callback(bytes32,bytes)')), _requestId, _data);
//     }

//     bytes memory _requestData =
//       abi.encode(IMultipleCallbacksModule.RequestParameters({targets: _targets, data: _targetData}));

//     // Check: does it revert if the target has no code?
//     vm.expectRevert(IMultipleCallbacksModule.MultipleCallbackModule_TargetHasNoCode.selector);
//     vm.prank(address(oracle));
//     multipleCallbackModule.setupRequest(_requestId, _requestData);
//   }

//   function test_setUpMultipleTargets(bytes32 _requestId, address[] memory _targets, bytes memory _data) public {
//     vm.assume(_targets.length > 1);

//     // Hardcoding data (as it is not the case tested) to avoid vm.assume issues
//     bytes[] memory _targetData = new bytes[](_targets.length);
//     for (uint256 _i = 0; _i < _targets.length; _i++) {
//       _assumeFuzzable(_targets[_i]);
//       vm.etch(_targets[_i], hex'069420');
//       _targetData[_i] = abi.encodeWithSelector(bytes4(keccak256('callback(bytes32,bytes)')), _requestId, _data);
//     }

//     bytes memory _requestData =
//       abi.encode(IMultipleCallbacksModule.RequestParameters({targets: _targets, data: _targetData}));

//     vm.prank(address(oracle));
//     multipleCallbackModule.setupRequest(_requestId, _requestData);

//     IMultipleCallbacksModule.RequestParameters memory _storedParams =
//       multipleCallbackModule.decodeRequestData(_requestId);
//     // Check: is the data properly stored?
//     assertEq(_storedParams.targets, _targets);
//   }
// }
