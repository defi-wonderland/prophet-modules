// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_ResponseDispute is IntegrationBase {
  function setUp() public override {
    super.setUp();

    // Create request
    _deposit(_accountingExtension, requester, usdc, _expectedBondSize);
    _createRequest();

    // Propose a response
    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);
    _proposeResponse();

    // Disputer approves the dispute module
    vm.prank(disputer);
    _accountingExtension.approveModule(address(_bondedDisputeModule));
  }

  /**
   * @notice Disputing a response should be reflected the oracle's state
   */
  function test_disputeResponse() public {
    _deposit(_accountingExtension, disputer, usdc, _expectedBondSize);

    vm.prank(disputer);
    bytes32 _disputeId = oracle.disputeResponse(mockRequest, mockResponse, mockDispute);

    // Check: the disputer is a participant now?
    assertTrue(oracle.isParticipant(_getId(mockRequest), disputer));

    // Check: the dispute status is Active?
    assertEq(uint256(oracle.disputeStatus(_disputeId)), uint256(IOracle.DisputeStatus.Active));

    // Check: dispute id is stored?
    assertEq(oracle.disputeOf(_getId(mockResponse)), _disputeId);

    // Check: creation time is correct?
    assertEq(oracle.disputeCreatedAt(_disputeId), block.number);
  }

  /**
   * @notice Disputing a non-existent response should revert
   */
  function test_disputeResponse_nonExistentResponse(
    bytes32 _nonExistentResponseId
  ) public {
    vm.assume(_nonExistentResponseId != _getId(mockResponse));
    mockDispute.responseId = _nonExistentResponseId;

    vm.expectRevert(ValidatorLib.ValidatorLib_InvalidDisputeBody.selector);

    vm.prank(disputer);
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Sending an an invalid dispute in should revert
   */
  function test_disputeResponse_requestAndResponseMismatch(
    bytes32 _requestId
  ) public {
    vm.assume(_requestId != _getId(mockRequest));

    mockDispute.requestId = _requestId;

    vm.expectRevert(ValidatorLib.ValidatorLib_InvalidDisputeBody.selector);

    vm.prank(disputer);
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Revert if the disputer has no funds to bond
   */
  function test_disputeResponse_noBondedFunds() public {
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);

    vm.prank(disputer);
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Disputing a finalized response should revert
   */
  function test_disputeResponse_alreadyFinalized() public {
    vm.roll(_expectedDeadline + _baseDisputeWindow);
    oracle.finalize(mockRequest, mockResponse);

    vm.expectRevert(abi.encodeWithSelector(IOracle.Oracle_AlreadyFinalized.selector, _getId(mockRequest)));

    vm.prank(disputer);
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Disputing a response that has already been disputed should revert
   */
  function test_disputeResponse_alreadyDisputed() public {
    _deposit(_accountingExtension, disputer, usdc, _expectedBondSize);

    vm.prank(disputer);
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);

    vm.prank(disputer);
    vm.expectRevert(abi.encodeWithSelector(IOracle.Oracle_ResponseAlreadyDisputed.selector, _getId(mockResponse)));
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);
  }
}
