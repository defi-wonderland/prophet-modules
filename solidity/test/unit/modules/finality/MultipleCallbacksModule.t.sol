// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IModule} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IModule.sol';

import {
  MultipleCallbacksModule,
  IMultipleCallbacksModule
} from '../../../../contracts/modules/finality/MultipleCallbacksModule.sol';

contract BaseTest is Test, Helpers {
  // The target contract
  MultipleCallbacksModule public multipleCallbackModule;
  // A mock oracle
  IOracle public oracle;

  // Events
  event Callback(bytes32 indexed _request, address indexed _target, bytes _data);

  /**
   * @notice Deploy the target and mock oracle+accounting extension
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    multipleCallbackModule = new MultipleCallbacksModule(oracle);
  }
}

/**
 * @title MultipleCallback Module Unit tests
 */
contract MultipleCallbacksModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleNameReturnsName() public {
    assertEq(multipleCallbackModule.moduleName(), 'MultipleCallbacksModule');
  }
}

contract MultipleCallbacksModule_Unit_FinalizeRequests is BaseTest {
  /**
   * @notice Test that finalizeRequests calls the _target.callback with the correct data
   */
  function test_finalizeRequest(address[] calldata _targets, bytes[] calldata _data) public {
    vm.assume(_targets.length == _data.length);

    mockRequest.finalityModuleData =
      abi.encode(IMultipleCallbacksModule.RequestParameters({targets: _targets, data: _data}));
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;

    for (uint256 _i; _i < _targets.length; _i++) {
      address _target = _targets[_i];
      bytes calldata _calldata = _data[_i];

      // Skip precompiles, VM, console.log addresses, etc
      _assumeFuzzable(_target);
      _mockAndExpect(_target, _calldata, abi.encode());

      // Check: is the event emitted?
      vm.expectEmit(true, true, true, true, address(multipleCallbackModule));
      emit Callback(_requestId, _target, _calldata);
    }

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(multipleCallbackModule));
    emit RequestFinalized(_requestId, mockResponse, address(oracle));

    vm.prank(address(oracle));
    multipleCallbackModule.finalizeRequest(mockRequest, mockResponse, address(oracle));
  }

  /**
   * @notice Test that the finalizeRequests reverts if caller is not the oracle
   */
  function test_revertsIfWrongCaller(IOracle.Request calldata _request, address _caller) public {
    vm.assume(_caller != address(oracle));

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);
    vm.prank(_caller);
    multipleCallbackModule.finalizeRequest(_request, mockResponse, address(_caller));
  }
}
