// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_ResponseDispute is IntegrationBase {
  function setUp() public override {
    super.setUp();

    _deposit(_accountingExtension, requester, usdc, _expectedBondSize);
    _createRequest();

    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);
    _proposeResponse();

    vm.prank(disputer);
    _accountingExtension.approveModule(address(_bondedDisputeModule));
  }

  function test_disputeResponse() public {
    _deposit(_accountingExtension, disputer, usdc, _expectedBondSize);

    vm.prank(disputer);
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  function test_disputeResponse_nonExistentResponse(bytes32 _nonExistentResponseId) public {
    vm.assume(_nonExistentResponseId != _getId(mockResponse));
    mockDispute.responseId = _nonExistentResponseId;

    vm.expectRevert(IOracle.Oracle_InvalidDisputeBody.selector);

    vm.prank(disputer);
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  function test_disputeResponse_requestAndResponseMismatch() public {
    _deposit(_accountingExtension, requester, usdc, _expectedBondSize);

    // Second request
    mockRequest.nonce += 1;
    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);

    vm.prank(requester);
    bytes32 _secondRequestId = oracle.createRequest(mockRequest, _ipfsHash);

    mockResponse.requestId = _secondRequestId;

    vm.prank(proposer);
    oracle.proposeResponse(mockRequest, mockResponse);

    vm.expectRevert(IOracle.Oracle_InvalidDisputeBody.selector);

    vm.prank(disputer);
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  function test_disputeResponse_noBondedFunds() public {
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);

    vm.prank(disputer);
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  function test_disputeResponse_alreadyFinalized() public {
    vm.roll(_expectedDeadline + _baseDisputeWindow);
    oracle.finalize(mockRequest, mockResponse);

    vm.expectRevert(abi.encodeWithSelector(IOracle.Oracle_AlreadyFinalized.selector, _getId(mockRequest)));

    vm.prank(disputer);
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  function test_disputeResponse_alreadyDisputed() public {
    _deposit(_accountingExtension, disputer, usdc, _expectedBondSize);

    vm.prank(disputer);
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);

    vm.prank(disputer);
    vm.expectRevert(abi.encodeWithSelector(IOracle.Oracle_ResponseAlreadyDisputed.selector, _getId(mockResponse)));
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  // TODO: discuss and decide on the implementation of a dispute deadline
  //   function test_disputeResponse_afterDeadline(uint256 _timestamp) public {
  //     vm.assume(_timestamp > _expectedDeadline);
  //     _bondDisputerFunds();
  //     vm.warp(_timestamp);
  //     vm.prank(disputer);
  //     vm.expectRevert(abi.encodeWithSelector(IBondedDisputeModule.BondedDisputeModule_TooLateToDispute.selector, _responseId));
  //     oracle.disputeResponse(_requestId, _responseId);
  //   }
}
