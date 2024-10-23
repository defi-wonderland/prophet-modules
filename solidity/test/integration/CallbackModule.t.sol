// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_CallbackModule is IntegrationBase {
  IProphetCallback public callback;

  bytes32 internal _requestId;
  bytes internal _expectedData = bytes('a-well-formed-calldata');

  function setUp() public override {
    super.setUp();

    callback = new MockCallback();

    mockRequest.finalityModuleData =
      abi.encode(ICallbackModule.RequestParameters({target: address(callback), data: _expectedData}));
  }

  function test_finalizeExecutesCallback() public {
    _setupRequest();

    vm.expectCall(address(callback), abi.encodeCall(IProphetCallback.prophetCallback, (_expectedData)));

    // advance time past deadline
    vm.warp(block.timestamp + _expectedDeadline + _baseDisputeWindow);
    oracle.finalize(mockRequest, mockResponse);
  }

  function test_callbacksNeverRevert() public {
    MockFailCallback _target = new MockFailCallback();
    mockRequest.finalityModuleData =
      abi.encode(ICallbackModule.RequestParameters({target: address(_target), data: _expectedData}));
    _setupRequest();

    // expect call to target passing the expected data
    vm.expectCall(address(_target), abi.encodeCall(IProphetCallback.prophetCallback, (_expectedData)));

    vm.warp(block.timestamp + _expectedDeadline + _baseDisputeWindow);
    oracle.finalize(mockRequest, mockResponse);
  }

  function _setupRequest() internal {
    _resetMockIds();

    _deposit(_accountingExtension, requester, usdc, _expectedReward);
    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    _requestId = oracle.createRequest(mockRequest, _ipfsHash);
    vm.stopPrank();

    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);
    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    mockResponse.response = abi.encode(proposer, _requestId, bytes(''));
    oracle.proposeResponse(mockRequest, mockResponse, _createAccessControl());
    vm.stopPrank();
  }
}
