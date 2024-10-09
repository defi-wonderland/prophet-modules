// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {
  ContractCallRequestModule,
  IContractCallRequestModule
} from '../../contracts/modules/request/ContractCallRequestModule.sol';
import {MockCallee} from '../mocks/MockCallee.sol';
import './IntegrationBase.sol';

contract Integration_ContractCallRequest is IntegrationBase {
  address internal _finalizer = makeAddr('finalizer');
  string internal _url = 'an-url';
  string internal _body = 'a-body';

  MockCallee internal _target;
  ContractCallRequestModule internal _contractCallRequestModule;

  function setUp() public override {
    super.setUp();

    _deposit(_accountingExtension, requester, usdc, _expectedReward);
    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);

    _contractCallRequestModule = new ContractCallRequestModule(oracle);
    _target = new MockCallee();
  }

  function test_createRequest_finalizeEmptyResponse(bytes4 _selector, bytes calldata _data) public {
    mockRequest.requestModule = address(_contractCallRequestModule);

    vm.prank(requester);
    _accountingExtension.approveModule(address(mockRequest.requestModule));

    mockRequest.requestModuleData = abi.encode(
      IContractCallRequestModule.RequestParameters({
        target: address(_target),
        functionSelector: _selector,
        data: _data,
        accountingExtension: _accountingExtension,
        paymentToken: usdc,
        paymentAmount: _expectedReward
      })
    );

    vm.prank(requester);
    oracle.createRequest(mockRequest, _ipfsHash);

    // mock an empty response
    mockResponse =
      IOracle.Response({proposer: makeAddr('not-the-proposer'), requestId: bytes32(0), response: bytes('')});

    vm.warp(block.timestamp + 2 days);

    vm.prank(_finalizer);
    oracle.finalize(mockRequest, mockResponse);
  }

  function test_createRequest_finalizeValidResponse(bytes4 _selector, bytes calldata _data) public {
    mockRequest.requestModule = address(_contractCallRequestModule);

    vm.prank(requester);
    _accountingExtension.approveModule(address(mockRequest.requestModule));

    mockRequest.requestModuleData = abi.encode(
      IContractCallRequestModule.RequestParameters({
        target: address(_target),
        functionSelector: _selector,
        data: _data,
        accountingExtension: _accountingExtension,
        paymentToken: usdc,
        paymentAmount: _expectedReward
      })
    );

    vm.prank(requester);
    bytes32 _requestId = oracle.createRequest(mockRequest, _ipfsHash);

    mockResponse = IOracle.Response({proposer: proposer, requestId: _requestId, response: bytes('good-answer')});

    vm.prank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    vm.prank(proposer);
    oracle.proposeResponse(mockRequest, mockResponse);

    vm.warp(block.timestamp + _expectedDeadline);

    vm.prank(_finalizer);
    oracle.finalize(mockRequest, mockResponse);
  }
}
