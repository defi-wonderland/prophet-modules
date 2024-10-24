// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_MultipleCallbackModule is IntegrationBase {
  uint256 public constant CALLBACKS_AMOUNT = 255;
  IProphetCallback public callback;
  MultipleCallbacksModule public multipleCallbacksModule;

  bytes32 internal _requestId;

  function setUp() public override {
    super.setUp();

    multipleCallbacksModule = new MultipleCallbacksModule(oracle);
    mockRequest.finalityModule = address(multipleCallbacksModule);

    callback = new MockCallback();
  }

  function test_finalizeExecutesCallback() public {
    (address[] memory _targets, bytes[] memory _datas) = _createCallbacksData(address(callback), CALLBACKS_AMOUNT);
    mockRequest.finalityModuleData =
      abi.encode(IMultipleCallbacksModule.RequestParameters({targets: _targets, data: _datas}));

    _setupRequest();

    for (uint256 _i; _i < _datas.length; _i++) {
      vm.expectCall(address(_targets[_i]), abi.encodeCall(IProphetCallback.prophetCallback, (_datas[_i])));
    }

    vm.warp(block.timestamp + _expectedDeadline + _baseDisputeWindow);
    oracle.finalize(mockRequest, mockResponse);
  }

  function test_callbacksNeverRevert() public {
    callback = new MockFailCallback();

    (address[] memory _targets, bytes[] memory _datas) = _createCallbacksData(address(callback), CALLBACKS_AMOUNT);

    mockRequest.finalityModuleData =
      abi.encode(IMultipleCallbacksModule.RequestParameters({targets: _targets, data: _datas}));

    _setupRequest();

    // expect call to every target with the expected data
    for (uint256 _i; _i < _datas.length; _i++) {
      vm.expectCall(address(_targets[_i]), abi.encodeCall(IProphetCallback.prophetCallback, (_datas[_i])));
    }

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
    oracle.proposeResponse(mockRequest, mockResponse, mockAccessControl);
    vm.stopPrank();
  }

  function _createCallbacksData(
    address _target,
    uint256 _length
  ) internal pure returns (address[] memory _targets, bytes[] memory _datas) {
    _targets = new address[](_length);
    _datas = new bytes[](_length);
    for (uint256 _i; _i < _length; _i++) {
      _targets[_i] = _target;
      _datas[_i] = abi.encode(keccak256(abi.encode(_i)));
    }
  }
}
