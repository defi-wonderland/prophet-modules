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
  // Mock EOA proposer
  address public proposer = makeAddr('proposer');
  // Mock EOA disputer
  address public disputer = makeAddr('disputer');
  // Create a new dummy dispute
  IOracle.Dispute public mockDispute;
  // Create a new dummy response
  IOracle.Response public mockResponse;
  bytes32 public mockId = bytes32('69');

  event Callback(bytes32 indexed _request, address indexed _target, bytes _data);
  event RequestFinalized(bytes32 indexed _requestId, address _finalizer);

  /**
   * @notice Deploy the target and mock oracle+accounting extension
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    multipleCallbackModule = new MultipleCallbacksModule(oracle);
    mockDispute =
      IOracle.Dispute({disputer: disputer, proposer: proposer, responseId: bytes32('69'), requestId: bytes32('69')});
    mockResponse = IOracle.Response({proposer: proposer, requestId: mockId, response: bytes('')});
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
  function test_finalizeRequest(
    IOracle.Request calldata _request,
    address[1] calldata _targets,
    bytes[1] calldata __data
  ) public {
    bytes32 _requestId = _getId(_request);
    address _target = _targets[0];
    bytes calldata _data = __data[0];

    assumeNotPrecompile(_target);
    vm.assume(_target != address(vm));

    // Create and set some mock request data
    address[] memory _targetParams = new address[](1);
    _targetParams[0] = _targets[0];
    bytes[] memory _dataParams = new bytes[](1);
    _dataParams[0] = __data[0];

    _mockAndExpect(_target, _data, abi.encode());

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(multipleCallbackModule));
    emit Callback(_requestId, _target, _data);

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(multipleCallbackModule));
    emit RequestFinalized(_requestId, address(oracle));

    vm.prank(address(oracle));
    multipleCallbackModule.finalizeRequest(_request, mockResponse, address(oracle));
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
