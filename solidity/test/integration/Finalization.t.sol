// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_Finalization is IntegrationBase {
  address internal _finalizer = makeAddr('finalizer');
  address internal _callbackTarget = makeAddr('target');

  function setUp() public override {
    super.setUp();

    vm.etch(_callbackTarget, hex'069420');

    _setFinalizationModule(
      address(_callbackModule),
      abi.encode(ICallbackModule.RequestParameters({target: _callbackTarget, data: bytes('')}))
    );

    _deposit(_accountingExtension, requester, usdc, _expectedReward);
    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);
    _deposit(_accountingExtension, disputer, usdc, _expectedBondSize);
  }

  /**
   * @notice Test to check if another module can be set as callback module.
   */
  function test_targetIsAnotherModule() public {
    _setFinalizationModule(
      address(_callbackModule),
      abi.encode(
        ICallbackModule.RequestParameters({
          target: address(_callbackModule),
          data: abi.encodeWithSignature('callback()')
        })
      )
    );

    _createRequest();
    _proposeResponse();

    // Traveling to the end of the dispute window
    vm.roll(_expectedDeadline + 1 + _baseDisputeWindow);

    vm.prank(_finalizer);
    oracle.finalize(mockRequest, mockResponse);

    // Check: is response finalized?
    bytes32 _finalizedResponseId = oracle.finalizedResponseId(_getId(mockRequest));
    assertEq(_finalizedResponseId, _getId(mockResponse));
  }

  /**
   * @notice Finalization data is set and callback calls are made.
   */
  function test_makeAndIgnoreLowLevelCalls(
    bytes memory _calldata
  ) public {
    _setFinalizationModule(
      address(_callbackModule),
      abi.encode(ICallbackModule.RequestParameters({target: _callbackTarget, data: _calldata}))
    );

    _createRequest();
    _proposeResponse();

    // Traveling to the end of the dispute window
    vm.roll(_expectedDeadline + 1 + _baseDisputeWindow);

    // Check: all low-level calls are made?
    vm.expectCall(_callbackTarget, _calldata);

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

    mockResponse.response = abi.encode('nonexistent');
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
  function test_revertFinalizeInDisputeWindow(
    uint256 _block
  ) public {
    _block = bound(_block, block.number, _expectedDeadline - _baseDisputeWindow - 1);

    _createRequest();
    _proposeResponse();

    vm.roll(_block);

    // Check: reverts if called during the dispute window?
    vm.expectRevert(IBondedResponseModule.BondedResponseModule_TooEarlyToFinalize.selector);
    vm.prank(_finalizer);
    oracle.finalize(mockRequest, mockResponse);
  }

  /**
   * @notice Finalizing a request without disputes triggers callback calls and executes without reverting.
   */
  function test_finalizeWithUndisputedResponse(
    bytes calldata _calldata
  ) public {
    _setFinalizationModule(
      address(_callbackModule),
      abi.encode(ICallbackModule.RequestParameters({target: _callbackTarget, data: _calldata}))
    );

    _createRequest();
    _proposeResponse();

    // Traveling to the end of the dispute window
    vm.roll(_expectedDeadline + 1 + _baseDisputeWindow);

    vm.expectCall(_callbackTarget, _calldata);
    vm.prank(_finalizer);
    oracle.finalize(mockRequest, mockResponse);

    // Check: is response finalized?
    bytes32 _finalizedResponseId = oracle.finalizedResponseId(_getId(mockRequest));
    assertEq(_finalizedResponseId, _getId(mockResponse));
  }

  /**
   * @notice Finalizing a request before the disputing deadline reverts.
   */
  function test_revertFinalizeBeforeDeadline(
    bytes calldata _calldata
  ) public {
    _setFinalizationModule(
      address(_callbackModule),
      abi.encode(ICallbackModule.RequestParameters({target: _callbackTarget, data: _calldata}))
    );

    vm.expectCall(_callbackTarget, _calldata);

    _createRequest();
    _proposeResponse();

    vm.expectRevert(IBondedResponseModule.BondedResponseModule_TooEarlyToFinalize.selector);
    vm.prank(_finalizer);
    oracle.finalize(mockRequest, mockResponse);
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
