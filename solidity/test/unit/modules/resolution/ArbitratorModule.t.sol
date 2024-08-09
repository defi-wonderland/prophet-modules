// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IModule} from '@defi-wonderland/prophet-core/solidity/interfaces/IModule.sol';
import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';

import {
  ArbitratorModule,
  IArbitrator,
  IArbitratorModule
} from '../../../../contracts/modules/resolution/ArbitratorModule.sol';

/**
 * @dev Harness to set an entry in the requestData mapping, without triggering setup request hooks
 */
contract ForTest_ArbitratorModule is ArbitratorModule {
  constructor(IOracle _oracle) ArbitratorModule(_oracle) {}

  function forTest_setDisputeStatus(bytes32 _disputeId, IArbitratorModule.ArbitrationStatus _status) public {
    _disputeData[_disputeId] = _status;
  }
}

/**
 * @title Arbitrator Module Unit tests
 */
contract BaseTest is Test, Helpers {
  // The target contract
  ForTest_ArbitratorModule public arbitratorModule;
  // A mock oracle
  IOracle public oracle;
  // A mock arbitrator
  IArbitrator public arbitrator;

  // Events
  event ResolutionStarted(bytes32 indexed _requestId, bytes32 indexed _disputeId);
  event DisputeResolved(bytes32 indexed _requestId, bytes32 indexed _disputeId, IOracle.DisputeStatus _status);

  /**
   * @notice Deploy the target and mock oracle
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    arbitrator = IArbitrator(makeAddr('MockArbitrator'));
    vm.etch(address(arbitrator), hex'069420');

    arbitratorModule = new ForTest_ArbitratorModule(oracle);
  }
}

contract ArbitratorModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleNameReturnsName() public view {
    assertEq(arbitratorModule.moduleName(), 'ArbitratorModule');
  }
  /**
   * @notice Test that the decodeRequestData function returns the correct values
   */

  function test_decodeRequestData(address _arbitrator) public view {
    // Mock data
    bytes memory _requestData = abi.encode(_arbitrator);

    // Test: decode the given request data
    IArbitratorModule.RequestParameters memory _requestParameters = arbitratorModule.decodeRequestData(_requestData);

    // Check: decoded values match original values?
    assertEq(_requestParameters.arbitrator, _arbitrator);
  }

  /**
   * @notice Test that the status is correctly retrieved
   */
  function test_getStatus(uint256 _status, bytes32 _disputeId) public {
    vm.assume(_status <= uint256(IArbitratorModule.ArbitrationStatus.Resolved));
    IArbitratorModule.ArbitrationStatus _arbitratorStatus = IArbitratorModule.ArbitrationStatus(_status);

    // Store the mock dispute
    arbitratorModule.forTest_setDisputeStatus(_disputeId, _arbitratorStatus);

    // Check: The correct status is returned?
    assertEq(uint256(arbitratorModule.getStatus(_disputeId)), uint256(_status));
  }

  /**
   * @notice Test that the validateParameters function correctly checks the parameters
   */
  function test_validateParameters(IArbitratorModule.RequestParameters calldata _params) public view {
    if (_params.arbitrator == address(0)) {
      assertFalse(arbitratorModule.validateParameters(abi.encode(_params)));
    } else {
      assertTrue(arbitratorModule.validateParameters(abi.encode(_params)));
    }
  }
}

contract ArbitratorModule_Unit_StartResolution is BaseTest {
  /**
   * @notice Test that the escalate function works as expected
   */
  function test_startResolution(address _arbitrator) public assumeFuzzable(_arbitrator) {
    mockRequest.resolutionModuleData = abi.encode(_arbitrator);
    bytes32 _requestId = _getId(mockRequest);

    mockResponse.requestId = _requestId;
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect the callback to the arbitrator
    _mockAndExpect(
      _arbitrator, abi.encodeCall(arbitrator.resolve, (mockRequest, mockResponse, mockDispute)), abi.encode(bytes(''))
    );

    vm.prank(address(oracle));
    arbitratorModule.startResolution(_disputeId, mockRequest, mockResponse, mockDispute);

    // Check: is status now Escalated?
    assertEq(uint256(arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Active));
  }

  function test_emitsEvent(address _arbitrator) public assumeFuzzable(_arbitrator) {
    mockRequest.resolutionModuleData = abi.encode(_arbitrator);
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect the callback to the arbitrator
    _mockAndExpect(
      _arbitrator, abi.encodeCall(arbitrator.resolve, (mockRequest, mockResponse, mockDispute)), abi.encode(bytes(''))
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(arbitratorModule));
    emit ResolutionStarted(mockDispute.requestId, _disputeId);

    vm.prank(address(oracle));
    arbitratorModule.startResolution(_disputeId, mockRequest, mockResponse, mockDispute);
  }

  function test_revertInvalidCaller(address _caller) public {
    vm.assume(_caller != address(oracle));

    // Check: does it revert if the caller is not the Oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);

    vm.prank(_caller);
    arbitratorModule.startResolution(_getId(mockDispute), mockRequest, mockResponse, mockDispute);
  }

  function test_revertIfEmptyArbitrator() public {
    mockRequest.resolutionModuleData = abi.encode(address(0));
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;
    mockDispute.requestId = _requestId;

    // Check: revert?
    vm.expectRevert(IArbitratorModule.ArbitratorModule_InvalidArbitrator.selector);

    // Test: escalate the dispute
    vm.prank(address(oracle));
    arbitratorModule.startResolution(_getId(mockDispute), mockRequest, mockResponse, mockDispute);
  }
}

contract ArbitratorModule_Unit_ResolveDispute is BaseTest {
  /**
   * @notice Test that the resolve function works as expected
   */
  function test_resolveDispute(uint256 _status, address _arbitrator) public assumeFuzzable(_arbitrator) {
    _status = bound(_status, uint256(IOracle.DisputeStatus.Escalated) + 1, uint256(IOracle.DisputeStatus.Lost));
    IOracle.DisputeStatus _arbitratorStatus = IOracle.DisputeStatus(_status);

    mockRequest.resolutionModuleData = abi.encode(_arbitrator);
    mockDispute.requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(oracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    // Mock and expect getAnswer to be called on the arbitrator
    _mockAndExpect(
      address(_arbitrator), abi.encodeCall(arbitrator.getAnswer, (_disputeId)), abi.encode(_arbitratorStatus)
    );

    // Mock and expect IOracle.updateDisputeStatus to be called
    _mockAndExpect(
      address(oracle),
      abi.encodeCall(oracle.updateDisputeStatus, (mockRequest, mockResponse, mockDispute, _arbitratorStatus)),
      abi.encode()
    );

    vm.prank(address(oracle));
    arbitratorModule.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);

    // Check: is status now Resolved?
    assertEq(uint256(arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Resolved));
  }

  function test_revertsIfInvalidResolveStatus(uint256 _status, address _arbitrator) public assumeFuzzable(_arbitrator) {
    vm.assume(_status <= uint256(IOracle.DisputeStatus.Escalated));
    IOracle.DisputeStatus _arbitratorStatus = IOracle.DisputeStatus(_status);

    mockRequest.resolutionModuleData = abi.encode(_arbitrator);
    mockDispute.requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(oracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    // Mock and expect getAnswer to be called on the arbitrator
    _mockAndExpect(
      address(_arbitrator), abi.encodeCall(arbitrator.getAnswer, (_disputeId)), abi.encode(_arbitratorStatus)
    );

    // Check: does it revert if the resolution status is invalid?
    vm.expectRevert(IArbitratorModule.ArbitratorModule_InvalidResolutionStatus.selector);

    vm.prank(address(oracle));
    arbitratorModule.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);
  }

  function test_emitsEvent(uint256 _status, address _arbitrator) public assumeFuzzable(_arbitrator) {
    _status = bound(_status, uint256(IOracle.DisputeStatus.Escalated) + 1, uint256(IOracle.DisputeStatus.Lost));
    IOracle.DisputeStatus _arbitratorStatus = IOracle.DisputeStatus(_status);

    mockRequest.resolutionModuleData = abi.encode(_arbitrator);
    mockDispute.requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(oracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    // Mock and expect getAnswer to be called on the arbitrator
    _mockAndExpect(_arbitrator, abi.encodeCall(arbitrator.getAnswer, (_disputeId)), abi.encode(_arbitratorStatus));

    // Mock and expect IOracle.updateDisputeStatus to be called
    _mockAndExpect(
      address(oracle),
      abi.encodeCall(oracle.updateDisputeStatus, (mockRequest, mockResponse, mockDispute, _arbitratorStatus)),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(arbitratorModule));
    emit DisputeResolved(_getId(mockRequest), _disputeId, _arbitratorStatus);

    vm.prank(address(oracle));
    arbitratorModule.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice resolve dispute reverts if the dispute status isn't Active
   */
  function test_revertIfInvalidDispute(IOracle.Request calldata _request) public {
    // Test the 3 different invalid status (None, Won, Lost)
    for (uint256 _status; _status < uint256(type(IOracle.DisputeStatus).max); _status++) {
      if (IOracle.DisputeStatus(_status) == IOracle.DisputeStatus.Escalated) continue;
      mockDispute.requestId = _getId(_request);
      bytes32 _disputeId = _getId(mockDispute);

      // Mock and expect IOracle.disputeStatus to be called
      _mockAndExpect(
        address(oracle), abi.encodeCall(oracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus(_status))
      );

      vm.expectRevert(IArbitratorModule.ArbitratorModule_InvalidDisputeId.selector);

      vm.prank(address(oracle));
      arbitratorModule.resolveDispute(_disputeId, _request, mockResponse, mockDispute);
    }
  }

  /**
   * @notice Test that the resolve function reverts if the caller isn't the arbitrator
   */
  function test_revertIfWrongSender(address _caller) public {
    vm.assume(_caller != address(oracle));

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);

    vm.prank(_caller);
    arbitratorModule.resolveDispute(_getId(mockDispute), mockRequest, mockResponse, mockDispute);
  }
}
