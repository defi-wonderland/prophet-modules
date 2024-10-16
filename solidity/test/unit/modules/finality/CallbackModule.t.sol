// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IModule} from '@defi-wonderland/prophet-core/solidity/interfaces/IModule.sol';
import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';

import {CallbackModule, ICallbackModule} from '../../../../contracts/modules/finality/CallbackModule.sol';

import {IProphetCallback} from '../../../../interfaces/IProphetCallback.sol';

/**
 * @title Callback Module Unit tests
 */
contract BaseTest is Test, Helpers {
  // The target contract
  CallbackModule public callbackModule;
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

    callbackModule = new CallbackModule(oracle);
  }

  function targetHasBytecode(address _target) public view returns (bool _hasBytecode) {
    uint256 _size;
    assembly {
      _size := extcodesize(_target)
    }
    _hasBytecode = _size > 0;
  }
}

contract CallbackModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleNameReturnsName() public view {
    assertEq(callbackModule.moduleName(), 'CallbackModule');
  }

  /**
   * @notice Test that the decodeRequestData function returns the correct values
   */
  function test_decodeRequestData(address _target, bytes memory _data) public view {
    // Create and set some mock request data
    bytes memory _requestData = abi.encode(ICallbackModule.RequestParameters({target: _target, data: _data}));

    // Decode the given request data
    ICallbackModule.RequestParameters memory _params = callbackModule.decodeRequestData(_requestData);

    // Check: decoded values match original values?
    assertEq(_params.target, _target);
    assertEq(_params.data, _data);
  }

  /**
   * @notice Test that the validateParameters function correctly checks the parameters
   */
  function test_validateParameters(ICallbackModule.RequestParameters calldata _params) public view {
    if (address(_params.target) == address(0) || _params.data.length == 0 || !targetHasBytecode(_params.target)) {
      assertFalse(callbackModule.validateParameters(abi.encode(_params)));
    } else {
      assertTrue(callbackModule.validateParameters(abi.encode(_params)));
    }
  }
}

contract CallbackModule_Unit_FinalizeRequest is BaseTest {
  /**
   * @notice Test that finalizeRequest emits events
   */
  function test_emitsEvents(address _proposer, address _target, bytes calldata _data) public assumeFuzzable(_target) {
    mockRequest.finalityModuleData = abi.encode(ICallbackModule.RequestParameters({target: _target, data: _data}));
    mockResponse.requestId = _getId(mockRequest);

    // Mock and expect the callback
    _mockAndExpect(_target, abi.encodeWithSelector(IProphetCallback.prophetCallback.selector, _data), abi.encode(''));

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(callbackModule));
    emit Callback(mockResponse.requestId, _target, _data);

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(callbackModule));
    emit RequestFinalized(mockResponse.requestId, mockResponse, _proposer);

    vm.prank(address(oracle));
    callbackModule.finalizeRequest(mockRequest, mockResponse, _proposer);
  }

  /**
   * @notice Test that finalizeRequest triggers the callback
   */
  function test_triggersCallback(
    address _proposer,
    address _target,
    bytes calldata _data
  ) public assumeFuzzable(_target) {
    mockRequest.finalityModuleData = abi.encode(ICallbackModule.RequestParameters({target: _target, data: _data}));
    mockResponse.requestId = _getId(mockRequest);

    // Mock and expect the callback
    _mockAndExpect(_target, abi.encodeWithSelector(IProphetCallback.prophetCallback.selector, _data), abi.encode(''));

    vm.prank(address(oracle));
    callbackModule.finalizeRequest(mockRequest, mockResponse, _proposer);
  }

  function test_finalizationSucceedsWhenCallbackReverts(
    address _proposer,
    address _target,
    bytes calldata _data
  ) public assumeFuzzable(_target) {
    mockRequest.finalityModuleData = abi.encode(ICallbackModule.RequestParameters({target: _target, data: _data}));
    mockResponse.requestId = _getId(mockRequest);

    // Mock revert and expect the callback
    vm.mockCallRevert(
      _target, abi.encodeWithSelector(IProphetCallback.prophetCallback.selector, _data), abi.encode('err')
    );
    vm.expectCall(_target, abi.encodeWithSelector(IProphetCallback.prophetCallback.selector, _data));

    vm.prank(address(oracle));
    callbackModule.finalizeRequest(mockRequest, mockResponse, _proposer);
  }

  /**
   * @notice Test that the finalizeRequest reverts if caller is not the oracle
   */
  function test_revertsIfWrongCaller(ICallbackModule.RequestParameters calldata _data, address _caller) public {
    vm.assume(_caller != address(oracle));

    mockRequest.finalityModuleData = abi.encode(_data);
    mockResponse.requestId = _getId(mockRequest);

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);

    vm.prank(_caller);
    callbackModule.finalizeRequest(mockRequest, mockResponse, _caller);
  }
}
