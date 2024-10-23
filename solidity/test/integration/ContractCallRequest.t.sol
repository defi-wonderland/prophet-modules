// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {
  ContractCallRequestModule,
  IContractCallRequestModule
} from '../../contracts/modules/request/ContractCallRequestModule.sol';
import {MockCallee} from '../mocks/MockCallee.sol';
import './IntegrationBase.sol';

contract Integration_ContractCallRequest is IntegrationBase {
  ContractCallRequestModule public contractCallRequestModule;

  address internal _finalizer = makeAddr('finalizer');
  string internal _url = 'an-url';
  string internal _body = 'a-body';

  bytes4 internal _selector = bytes4(0xBaadF00d);
  bytes internal _calldata = bytes('well-formed-calldata');

  MockCallee internal _target;

  function setUp() public override {
    super.setUp();

    _deposit(_accountingExtension, requester, usdc, _expectedReward);
    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);

    contractCallRequestModule = new ContractCallRequestModule(oracle);
    _target = new MockCallee();

    mockRequest.requestModule = address(contractCallRequestModule);
    mockRequest.requestModuleData = abi.encode(
      IContractCallRequestModule.RequestParameters({
        target: address(_target),
        functionSelector: _selector,
        data: _calldata,
        accountingExtension: _accountingExtension,
        paymentToken: usdc,
        paymentAmount: _expectedReward
      })
    );
    vm.prank(requester);
    _accountingExtension.approveModule(address(mockRequest.requestModule));
  }

  function test_createRequest_finalizeEmptyResponse() public {
    vm.prank(requester);
    bytes32 _requestId = oracle.createRequest(mockRequest, _ipfsHash);
    uint256 _requestCreatedAt = oracle.requestCreatedAt(_requestId);

    // mock an empty response
    mockResponse = IOracle.Response({proposer: address(0), requestId: bytes32(0), response: bytes('')});

    assertEq(oracle.responseCreatedAt(_getId(mockResponse)), 0);

    // expect call to accounting to release requester's funds
    vm.expectCall(
      address(_accountingExtension),
      abi.encodeCall(IAccountingExtension.release, (mockRequest.requester, _requestId, usdc, _expectedReward))
    );

    vm.warp(_requestCreatedAt + _expectedDeadline);
    vm.prank(_finalizer);
    oracle.finalize(mockRequest, mockResponse);
  }

  function test_createRequest_finalizeValidResponse() public {
    vm.prank(requester);
    bytes32 _requestId = oracle.createRequest(mockRequest, _ipfsHash);

    mockResponse = IOracle.Response({proposer: proposer, requestId: _requestId, response: bytes('good-answer')});

    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    oracle.proposeResponse(mockRequest, mockResponse, _createAccessControl());
    vm.stopPrank();

    // expect call to accounting to pay the proposer
    vm.expectCall(
      address(_accountingExtension),
      abi.encodeCall(
        IAccountingExtension.pay,
        (mockResponse.requestId, mockRequest.requester, mockResponse.proposer, usdc, _expectedReward)
      )
    );

    vm.warp(block.timestamp + _expectedDeadline);
    vm.prank(_finalizer);
    oracle.finalize(mockRequest, mockResponse);
  }
}
