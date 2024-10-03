// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_MultipleCallbackModule is IntegrationBase {
  IProphetCallback internal _callback;
  MultipleCallbacksModule internal _multipleCallbacksModule;

  bytes32 internal _requestId;
  uint256 internal _correctValue = 123;

  function setUp() public override {
    super.setUp();

    _multipleCallbacksModule = new MultipleCallbacksModule(oracle);
    mockRequest.finalityModule = address(_multipleCallbacksModule);

    _callback = new MockCallback();
  }

  function test_finalizeExecutesCallback(bytes memory _data, uint8 _length) public {
    address[] memory _targets = new address[](_length);
    bytes[] memory _datas = new bytes[](_length);
    for (uint256 _i; _i < _length; _i++) {
      _targets[_i] = address(_callback);
      _datas[_i] = _data;
    }

    mockRequest.finalityModuleData =
      abi.encode(IMultipleCallbacksModule.RequestParameters({targets: _targets, data: _datas}));
    _resetMockIds();

    //
    _deposit(_accountingExtension, requester, usdc, _expectedReward);
    vm.prank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    vm.prank(requester);
    _requestId = oracle.createRequest(mockRequest, _ipfsHash);

    //
    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);
    vm.prank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    mockResponse.response = abi.encode(proposer, _requestId, _correctValue);
    vm.prank(proposer);
    oracle.proposeResponse(mockRequest, mockResponse);

    vm.warp(_expectedDeadline + _baseDisputeWindow);

    oracle.finalize(mockRequest, mockResponse);
  }

  function test_callbacksNeverRevert(uint8 _length) public {
    _callback = new MockFailCallback();

    address[] memory _targets = new address[](_length);
    bytes[] memory _datas = new bytes[](_length);
    for (uint256 _i; _i < _length; _i++) {
      _targets[_i] = address(_callback);
      _datas[_i] = new bytes(0);
    }
    mockRequest.finalityModuleData =
      abi.encode(IMultipleCallbacksModule.RequestParameters({targets: _targets, data: _datas}));
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
