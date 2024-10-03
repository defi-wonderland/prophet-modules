// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_CallbackModule is IntegrationBase {
  IProphetCallback internal _callback;

  bytes32 internal _requestId;
  uint256 internal _correctValue;

  function setUp() public override {
    super.setUp();

    _callback = new MockCallback();
  }

  function test_finalizeExecutesCallback(bytes memory _data) public {
    mockRequest.finalityModuleData =
      abi.encode(ICallbackModule.RequestParameters({target: address(_callback), data: _data}));
    _resetMockIds();

    // create request
    _deposit(_accountingExtension, requester, usdc, _expectedReward);
    vm.prank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    vm.prank(requester);
    _requestId = oracle.createRequest(mockRequest, _ipfsHash);

    // propose response
    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);
    vm.prank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    mockResponse.response = abi.encode(proposer, _requestId, _correctValue);
    vm.prank(proposer);
    oracle.proposeResponse(mockRequest, mockResponse);

    // advance time past deadline
    vm.warp(_expectedDeadline + _baseDisputeWindow);

    oracle.finalize(mockRequest, mockResponse);
  }

  function test_callbacksNeverRevert(bytes memory _data) public {
    mockRequest.finalityModuleData =
      abi.encode(ICallbackModule.RequestParameters({target: address(new MockFailCallback()), data: _data}));
    _resetMockIds();

    _deposit(_accountingExtension, requester, usdc, _expectedReward);
    vm.prank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    vm.prank(requester);
    _requestId = oracle.createRequest(mockRequest, _ipfsHash);

    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);
    vm.prank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    mockResponse.response = abi.encode(proposer, _requestId, _correctValue);
    vm.prank(proposer);
    oracle.proposeResponse(mockRequest, mockResponse);

    vm.warp(_expectedDeadline + _baseDisputeWindow);

    oracle.finalize(mockRequest, mockResponse);
  }
}
