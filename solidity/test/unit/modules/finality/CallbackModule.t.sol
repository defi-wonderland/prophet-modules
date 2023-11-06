// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IModule} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IModule.sol';

import {CallbackModule, ICallbackModule} from '../../../../contracts/modules/finality/CallbackModule.sol';

/**
 * @title Callback Module Unit tests
 */
contract BaseTest is Test, Helpers {
  // The target contract
  CallbackModule public callbackModule;
  // A mock oracle
  IOracle public oracle;
  // // Mock request
  // IOracle.Request internal _mockRequest;
  // // Mock response
  // IOracle.Response internal _mockResponse;

  event Callback(bytes32 indexed _request, address indexed _target, bytes _data);
  event RequestFinalized(bytes32 indexed _requestId, address _finalizer);

  /**
   * @notice Deploy the target and mock oracle+accounting extension
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    callbackModule = new CallbackModule(oracle);
  }
}

contract CallbackModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleNameReturnsName() public {
    assertEq(callbackModule.moduleName(), 'CallbackModule');
  }

  /**
   * @notice Test that the decodeRequestData function returns the correct values
   */
  function test_decodeRequestData(bytes32 _requestId, address _target, bytes memory _data) public {
    // Create and set some mock request data
    bytes memory _requestData = abi.encode(ICallbackModule.RequestParameters({target: _target, data: _data}));
    // callbackModule.forTest_setRequestData(_requestId, _requestData);

    // Decode the given request data
    ICallbackModule.RequestParameters memory _params = callbackModule.decodeRequestData(_requestData);

    // Check: decoded values match original values?
    assertEq(_params.target, _target);
    assertEq(_params.data, _data);
  }
}

contract CallbackModule_Unit_FinalizeRequest is BaseTest {
  /**
   * @notice Test that finalizeRequest calls the _target.callback with the correct data
   */
  function test_triggersCallback(
    bytes32 _requestId,
    address _proposer,
    address _target,
    IOracle.Request memory _request,
    bytes calldata _data
  ) public assumeFuzzable(_target) {
    _request.finalityModuleData = abi.encode(ICallbackModule.RequestParameters({target: _target, data: _data}));

    IOracle.Response memory _mockResponse =
      IOracle.Response({proposer: _proposer, requestId: _requestId, response: abi.encode(bytes32('response'))});

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(callbackModule));
    emit Callback(_requestId, _target, _data);

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(callbackModule));
    emit RequestFinalized(_requestId, _proposer);

    vm.prank(address(oracle));
    callbackModule.finalizeRequest(_request, _mockResponse, _proposer);
  }

  /**
   * @notice Test that the finalizeRequest reverts if caller is not the oracle
   */
  function test_revertsIfWrongCaller(
    bytes32 _requestId,
    address _proposer,
    address _target,
    IOracle.Request memory _request,
    bytes calldata _data
  ) public {
    vm.assume(_proposer != address(oracle));

    _request.finalityModuleData = abi.encode(ICallbackModule.RequestParameters({target: _target, data: _data}));

    IOracle.Response memory _mockResponse =
      IOracle.Response({proposer: _proposer, requestId: _requestId, response: abi.encode(bytes32('response'))});

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(abi.encodeWithSelector(IModule.Module_OnlyOracle.selector));

    vm.prank(_proposer);
    callbackModule.finalizeRequest(_request, _mockResponse, _proposer);
  }
}
