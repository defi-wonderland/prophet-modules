// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IModule} from '@defi-wonderland/prophet-core/solidity/interfaces/IModule.sol';
import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';

import {
  IMultipleCallbacksModule,
  MultipleCallbacksModule
} from '../../../../contracts/modules/finality/MultipleCallbacksModule.sol';

import {IProphetCallback} from '../../../../interfaces/IProphetCallback.sol';

contract BaseTest is Test, Helpers {
  // The target contract
  MultipleCallbacksModule public multipleCallbacksModule;
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

    multipleCallbacksModule = new MultipleCallbacksModule(oracle);
  }

  function targetHasBytecode(address _target) public view returns (bool _hasBytecode) {
    uint256 _size;
    assembly {
      _size := extcodesize(_target)
    }
    _hasBytecode = _size > 0;
  }
}

/**
 * @title MultipleCallback Module Unit tests
 */
contract MultipleCallbacksModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleNameReturnsName() public view {
    assertEq(multipleCallbacksModule.moduleName(), 'MultipleCallbacksModule');
  }

  /**
   * @notice Test that the validateParameters function correctly checks the parameters
   */
  function test_validateParameters(IMultipleCallbacksModule.RequestParameters calldata _params) public view {
    bool _valid = true;
    for (uint256 _i; _i < _params.targets.length; ++_i) {
      if (_params.targets[_i] == address(0) || !targetHasBytecode(_params.targets[_i])) {
        _valid = false;
      }
    }

    for (uint256 _i; _i < _params.data.length; ++_i) {
      if (_params.data[_i].length == 0) {
        _valid = false;
      }
    }

    if (!_valid) {
      assertFalse(multipleCallbacksModule.validateParameters(abi.encode(_params)));
    } else {
      assertTrue(multipleCallbacksModule.validateParameters(abi.encode(_params)));
    }
  }
}

contract MultipleCallbacksModule_Unit_FinalizeRequests is BaseTest {
  /**
   * @notice Test that finalizeRequests calls the _target.callback with the correct data
   */
  function test_finalizeRequest(address[10] calldata _fuzzedTargets, bytes[10] calldata _fuzzedData) public {
    address[] memory _targets = new address[](_fuzzedTargets.length);
    bytes[] memory _data = new bytes[](_fuzzedTargets.length);

    // Copying the values to fresh arrays that we can use to build `RequestParameters`
    for (uint256 _i; _i < _fuzzedTargets.length; _i++) {
      _targets[_i] = _fuzzedTargets[_i];
      _data[_i] = _fuzzedData[_i];
    }

    mockRequest.finalityModuleData =
      abi.encode(IMultipleCallbacksModule.RequestParameters({targets: _targets, data: _data}));
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;

    for (uint256 _i; _i < _targets.length; _i++) {
      address _target = _targets[_i];
      bytes memory _calldata = _data[_i];

      // Skip precompiles, VM, console.log addresses, etc
      _assumeFuzzable(_target);
      _mockAndExpect(
        _target, abi.encodeWithSelector(IProphetCallback.prophetCallback.selector, _calldata), abi.encode('')
      );

      // Check: is the event emitted?
      vm.expectEmit(true, true, true, true, address(multipleCallbacksModule));
      emit Callback(_requestId, _target, _calldata);
    }

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(multipleCallbacksModule));
    emit RequestFinalized(_requestId, mockResponse, address(oracle));

    vm.prank(address(oracle));
    multipleCallbacksModule.finalizeRequest(mockRequest, mockResponse, address(oracle));
  }

  function test_finalizationSucceedsWhenCallbacksRevert(
    address[10] calldata _fuzzedTargets,
    bytes[10] calldata _fuzzedData
  ) public {
    address[] memory _targets = new address[](_fuzzedTargets.length);
    bytes[] memory _data = new bytes[](_fuzzedTargets.length);

    // Copying the values to fresh arrays that we can use to build `RequestParameters`
    for (uint256 _i; _i < _fuzzedTargets.length; _i++) {
      _targets[_i] = _fuzzedTargets[_i];
      _data[_i] = _fuzzedData[_i];
    }

    mockRequest.finalityModuleData =
      abi.encode(IMultipleCallbacksModule.RequestParameters({targets: _targets, data: _data}));
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;

    for (uint256 _i; _i < _targets.length; _i++) {
      address _target = _targets[_i];
      bytes memory _calldata = _data[_i];

      // Skip precompiles, VM, console.log addresses, etc
      _assumeFuzzable(_target);
      vm.mockCallRevert(
        _target, abi.encodeWithSelector(IProphetCallback.prophetCallback.selector, _calldata), abi.encode('err')
      );
      vm.expectCall(_target, abi.encodeWithSelector(IProphetCallback.prophetCallback.selector, _calldata));

      // Check: is the event emitted?
      vm.expectEmit(true, true, true, true, address(multipleCallbacksModule));
      emit Callback(_requestId, _target, _calldata);
    }

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(multipleCallbacksModule));
    emit RequestFinalized(_requestId, mockResponse, address(oracle));

    vm.prank(address(oracle));
    multipleCallbacksModule.finalizeRequest(mockRequest, mockResponse, address(oracle));
  }

  /**
   * @notice Test that the finalizeRequests reverts if caller is not the oracle
   */
  function test_revertsIfWrongCaller(IOracle.Request calldata _request, address _caller) public {
    vm.assume(_caller != address(oracle));

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);
    vm.prank(_caller);
    multipleCallbacksModule.finalizeRequest(_request, mockResponse, address(_caller));
  }

  function test_decodeRequestData(address[] memory _targets, bytes[] memory _data) public view {
    // Create and set some mock request data
    bytes memory _requestData = abi.encode(IMultipleCallbacksModule.RequestParameters({targets: _targets, data: _data}));

    // Decode the given request data
    IMultipleCallbacksModule.RequestParameters memory _params = multipleCallbacksModule.decodeRequestData(_requestData);

    // Check: decoded values match original values?
    assertEq(_params.targets, _targets);
    assertEq(_params.data, _data);
  }
}
