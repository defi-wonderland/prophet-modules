// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_Finalization is IntegrationBase {
  MockAtomicArbitrator internal _mockAtomicArbitrator;
  address internal _finalizer = makeAddr('finalizer');

  function setUp() public override {
    super.setUp();

    vm.prank(governance);
    _mockAtomicArbitrator = new MockAtomicArbitrator(oracle);

    _deposit(_accountingExtension, requester, usdc, _expectedReward);
    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);
    _deposit(_accountingExtension, disputer, usdc, _expectedBondSize);
  }

  /**
   * @notice Finalization data is set and callback calls are made.
   */
  function test_makeAndIgnoreLowLevelCalls(bytes memory _calldata) public {
    _setFinalizationModule(
      address(_callbackModule),
      abi.encode(ICallbackModule.RequestParameters({target: address(_mockCallback), data: _calldata}))
    );

    _createRequest();
    _proposeResponse();

    // Traveling to the end of the dispute window
    vm.warp(block.timestamp + _expectedDeadline + 1 + _baseDisputeWindow);

    // Check: all external calls are made?
    vm.expectCall(address(_mockCallback), abi.encodeWithSelector(IProphetCallback.prophetCallback.selector, _calldata));

    vm.prank(_finalizer);
    oracle.finalize(mockRequest, mockResponse);

    // Check: is response finalized?
    bytes32 _finalizedResponseId = oracle.finalizedResponseId(_getId(mockRequest));
    assertEq(_finalizedResponseId, _getId(mockResponse));
  }

  /**
   * @notice Finalizing a request that has no response reverts.
   */
  function test_revertFinalizeIfNoResponse() public {
    _createRequest();

    // Check: reverts if request has no response?
    vm.expectRevert(IOracle.Oracle_InvalidResponse.selector);

    vm.prank(_finalizer);
    oracle.finalize(mockRequest, mockResponse);
  }

  /**
   * @notice Finalizing a request with a ongoing dispute reverts.
   */
  function test_revertFinalizeWithDisputedResponse() public {
    _createRequest();
    _proposeResponse();
    _disputeResponse();

    vm.prank(_finalizer);
    vm.expectRevert(IOracle.Oracle_InvalidFinalizedResponse.selector);
    oracle.finalize(mockRequest, mockResponse);
  }

  /**
   * @notice Finalizing a request with a ongoing dispute reverts.
   */
  function test_revertFinalizeInDisputeWindow(uint256 _timestamp) public {
    _timestamp = bound(_timestamp, block.timestamp, block.timestamp + _expectedDeadline - _baseDisputeWindow - 1);

    _createRequest();
    _proposeResponse();

    vm.warp(_timestamp);

    // Check: reverts if called during the dispute window?
    vm.expectRevert(IBondedResponseModule.BondedResponseModule_TooEarlyToFinalize.selector);
    vm.prank(_finalizer);
    oracle.finalize(mockRequest, mockResponse);
  }

  /**
   * @notice Finalizing a request without disputes triggers callback calls and executes without reverting.
   */
  function test_finalizeWithUndisputedResponse(bytes calldata _calldata) public {
    _setFinalizationModule(
      address(_callbackModule),
      abi.encode(ICallbackModule.RequestParameters({target: address(_mockCallback), data: _calldata}))
    );

    _createRequest();
    _proposeResponse();

    // Traveling to the end of the dispute window
    vm.warp(block.timestamp + _expectedDeadline + 1 + _baseDisputeWindow);

    vm.expectCall(address(_mockCallback), abi.encodeWithSelector(IProphetCallback.prophetCallback.selector, _calldata));
    vm.prank(_finalizer);
    oracle.finalize(mockRequest, mockResponse);

    // Check: is response finalized?
    bytes32 _finalizedResponseId = oracle.finalizedResponseId(_getId(mockRequest));
    assertEq(_finalizedResponseId, _getId(mockResponse));
  }

  /**
   * @notice Finalizing a request before the disputing deadline reverts.
   */
  function test_revertFinalizeBeforeDeadline(bytes calldata _calldata) public {
    _setFinalizationModule(
      address(_callbackModule),
      abi.encode(ICallbackModule.RequestParameters({target: address(_mockCallback), data: _calldata}))
    );

    vm.expectCall(address(_mockCallback), abi.encodeWithSelector(IProphetCallback.prophetCallback.selector, _calldata));

    _createRequest();
    _proposeResponse();

    vm.expectRevert(IBondedResponseModule.BondedResponseModule_TooEarlyToFinalize.selector);
    vm.prank(_finalizer);
    oracle.finalize(mockRequest, mockResponse);
  }

  /**
   * @notice Finalizing a request without a response.
   */
  function test_finalizeWithoutResponse(bytes calldata _calldata) public {
    _setFinalizationModule(
      address(_callbackModule),
      abi.encode(ICallbackModule.RequestParameters({target: address(_mockCallback), data: _calldata}))
    );

    _createRequest();

    // Traveling to the end of the dispute window
    vm.warp(block.timestamp + _expectedDeadline + 1 + _baseDisputeWindow);

    IOracle.Response memory _emptyResponse =
      IOracle.Response({proposer: address(0), requestId: bytes32(0), response: bytes('')});

    vm.expectCall(address(_mockCallback), abi.encodeWithSelector(IProphetCallback.prophetCallback.selector, _calldata));
    vm.prank(_finalizer);
    oracle.finalize(mockRequest, _emptyResponse);

    // Check: is response finalized?
    bytes32 _finalizedResponseId = oracle.finalizedResponseId(_getId(mockRequest));
    assertEq(_finalizedResponseId, bytes32(0));
  }

  /**
   * @notice Release unutilized response bond after finalization.
   */
  function test_releaseUnutilizedResponse(bytes calldata _calldata) public {
    _setFinalizationModule(
      address(_callbackModule),
      abi.encode(ICallbackModule.RequestParameters({target: address(_mockCallback), data: _calldata}))
    );

    // Create request, response and dispute it
    bytes32 _requestId = _createRequest();
    mockResponse.requestId = _requestId;
    bytes32 _responseId = _proposeResponse();

    IOracle.Response memory _disputedResponse = mockResponse;

    mockDispute.requestId = _requestId;
    mockDispute.responseId = _responseId;
    bytes32 _disputeId = _disputeResponse();

    IOracle.Dispute memory _dispute = mockDispute;

    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);
    mockResponse.response = bytes('second-answer');
    _proposeResponse();

    IOracle.Response memory _unutilizedResponse = mockResponse;

    // Traveling to the end of the dispute window
    vm.warp(block.timestamp + _expectedDeadline + 1 + _baseDisputeWindow);

    // Trying to release the bond reverts
    vm.expectRevert(IBondedResponseModule.BondedResponseModule_InvalidReleaseParameters.selector);
    vm.prank(proposer);
    _responseModule.releaseUnutilizedResponse(mockRequest, _unutilizedResponse);

    // Resolve dispute
    vm.prank(disputer);
    oracle.escalateDispute(mockRequest, _disputedResponse, _dispute);

    vm.mockCall(
      address(_mockArbitrator),
      abi.encodeCall(IArbitrator.getAnswer, (_disputeId)),
      abi.encode(IOracle.DisputeStatus.Lost)
    );
    assertEq(_accountingExtension.bondedAmountOf(proposer, usdc, _requestId), _expectedBondSize * 2);

    // Second step: resolving the dispute
    vm.prank(disputer);
    oracle.resolveDispute(mockRequest, _disputedResponse, _dispute);

    // After some time, finalize with an empty response
    vm.prank(_finalizer);
    oracle.finalize(mockRequest, _disputedResponse);

    assertEq(_accountingExtension.bondedAmountOf(proposer, usdc, _requestId), _expectedBondSize);

    // Check: is response finalized?
    bytes32 _finalizedResponseId = oracle.finalizedResponseId(_getId(mockRequest));
    assertEq(_finalizedResponseId, _getId(_disputedResponse));

    //    if (bondedAmountOf[_bonder][_token][_requestId] < _amount) revert AccountingExtension_InsufficientFunds();
    // Now the proposer should be able to release their unused response
    vm.prank(proposer);
    _responseModule.releaseUnutilizedResponse(mockRequest, _unutilizedResponse);
  }

  /**
   * @notice Updates the finalization module and its data.
   */
  function _setFinalizationModule(address _finalityModule, bytes memory _finalityModuleData) internal {
    mockRequest.finalityModule = _finalityModule;
    mockRequest.finalityModuleData = _finalityModuleData;
    _resetMockIds();
  }
}
