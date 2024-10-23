// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IHttpRequestModule} from '../../contracts/modules/request/HttpRequestModule.sol';
import './IntegrationBase.sol';

contract Integration_HttpRequest is IntegrationBase {
  IHttpRequestModule.HttpMethod public constant METHOD = IHttpRequestModule.HttpMethod.GET;

  address internal _finalizer = makeAddr('finalizer');
  string internal _url = 'an-url';
  string internal _body = 'a-body';

  function setUp() public override {
    super.setUp();

    _deposit(_accountingExtension, requester, usdc, _expectedReward);
    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);

    vm.prank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    mockRequest.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _url,
        method: METHOD,
        body: _body,
        accountingExtension: _accountingExtension,
        paymentToken: usdc,
        paymentAmount: _expectedReward
      })
    );
  }

  function test_createRequest_finalizeEmptyResponse() public {
    vm.prank(requester);
    bytes32 _requestId = oracle.createRequest(mockRequest, _ipfsHash);

    // mock an empty response
    mockResponse =
      IOracle.Response({proposer: makeAddr('not-the-proposer'), requestId: bytes32(0), response: bytes('')});

    // expect call to accounting to release requester's funds
    vm.expectCall(
      address(_accountingExtension),
      abi.encodeCall(IAccountingExtension.release, (mockRequest.requester, _requestId, usdc, _expectedReward))
    );

    vm.warp(block.timestamp + _expectedDeadline);

    vm.prank(_finalizer);
    oracle.finalize(mockRequest, mockResponse);
  }

  function test_createRequest_finalizeValidResponse() public {
    vm.prank(requester);
    bytes32 _requestId = oracle.createRequest(mockRequest, _ipfsHash);

    mockResponse = IOracle.Response({proposer: proposer, requestId: _requestId, response: bytes('good-answer')});

    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    oracle.proposeResponse(mockRequest, mockResponse, mockAccessControl);
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
