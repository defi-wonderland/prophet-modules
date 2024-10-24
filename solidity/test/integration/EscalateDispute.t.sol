// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_EscalateDispute is IntegrationBase {
  bytes32 internal _requestId;
  bytes32 internal _disputeId;
  uint256 internal _pledgeSize = _expectedBondSize;
  uint256 internal _tyingBuffer = 1 days;
  uint256 internal _expectedResponseDeadline = _expectedDeadline * 2;
  uint256 internal _disputeCreatedAt;

  function setUp() public override {
    super.setUp();

    _deposit(_bondEscalationAccounting, requester, usdc, _expectedReward);

    // Create a request with bond escalation module and arbitrator module
    mockRequest.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _expectedUrl,
        method: _expectedMethod,
        body: _expectedBody,
        accountingExtension: _bondEscalationAccounting,
        paymentToken: usdc,
        paymentAmount: _expectedReward
      })
    );

    mockRequest.responseModuleData = abi.encode(
      IBondedResponseModule.RequestParameters({
        accountingExtension: _bondEscalationAccounting,
        bondToken: usdc,
        bondSize: _expectedBondSize,
        deadline: _expectedResponseDeadline,
        disputeWindow: _baseDisputeWindow
      })
    );

    mockRequest.disputeModuleData = abi.encode(
      IBondEscalationModule.RequestParameters({
        accountingExtension: _bondEscalationAccounting,
        bondToken: usdc,
        bondSize: _expectedBondSize,
        maxNumberOfEscalations: 2,
        bondEscalationDeadline: _expectedDeadline,
        tyingBuffer: _tyingBuffer,
        disputeWindow: 0
      })
    );

    mockRequest.disputeModule = address(_bondEscalationModule);

    _resetMockIds();

    vm.startPrank(requester);
    _bondEscalationAccounting.approveModule(address(_requestModule));
    _requestId = oracle.createRequest(mockRequest, _ipfsHash);
    vm.stopPrank();

    // Propose a response and dispute it
    _deposit(_bondEscalationAccounting, proposer, usdc, _expectedBondSize);
    vm.startPrank(proposer);
    _bondEscalationAccounting.approveModule(address(_responseModule));
    oracle.proposeResponse(mockRequest, mockResponse);
    vm.stopPrank();

    _deposit(_bondEscalationAccounting, disputer, usdc, _expectedBondSize);
    vm.startPrank(disputer);
    _bondEscalationAccounting.approveModule(address(_bondEscalationModule));
    _disputeId = oracle.disputeResponse(mockRequest, mockResponse, mockDispute);
    vm.stopPrank();

    _disputeCreatedAt = oracle.disputeCreatedAt(_disputeId);
  }

  function test_disputeWonDispute() public {
    mockDispute.requestId = _requestId;

    // Bond escalation should call pledge
    vm.expectCall(
      address(_bondEscalationAccounting),
      abi.encodeCall(IBondEscalationAccounting.pledge, (disputer, mockRequest, mockDispute, usdc, _pledgeSize))
    );

    // Pledge for dispute
    _deposit(_bondEscalationAccounting, disputer, usdc, _pledgeSize * 3);
    vm.startPrank(disputer);
    _bondEscalationModule.pledgeForDispute(mockRequest, mockDispute);

    // Pledge revert if can be only surpassed by 1
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_CanOnlySurpassByOnePledge.selector);
    _bondEscalationModule.pledgeForDispute(mockRequest, mockDispute);
    vm.stopPrank();

    // Bond escalation should call pledge
    vm.expectCall(
      address(_bondEscalationAccounting),
      abi.encodeCall(IBondEscalationAccounting.pledge, (proposer, mockRequest, mockDispute, usdc, _pledgeSize))
    );

    // Pledge for dispute
    _deposit(_bondEscalationAccounting, proposer, usdc, _pledgeSize);
    vm.prank(proposer);
    _bondEscalationModule.pledgeAgainstDispute(mockRequest, mockDispute);

    // Get the bond escalation
    IBondEscalationModule.BondEscalation memory _bondEscalation = _bondEscalationModule.getEscalation(_requestId);

    // Check that the pledge was registered
    assertEq(_bondEscalationModule.pledgesAgainstDispute(_requestId, proposer), 1);
    assertEq(_bondEscalation.amountOfPledgesAgainstDispute, 1);

    vm.startPrank(disputer);

    // Pledge revert if break tie during tying buffer
    vm.warp(_disputeCreatedAt + _expectedDeadline + 1);
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_CannotBreakTieDuringTyingBuffer.selector);
    _bondEscalationModule.pledgeForDispute(mockRequest, mockDispute);

    // Pledege revert if bond escalation is over
    vm.warp(_disputeCreatedAt + _expectedDeadline + _tyingBuffer + 1);
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationOver.selector);
    _bondEscalationModule.pledgeForDispute(mockRequest, mockDispute);

    // Roll back the timestamp because we need to simulate the custom error "break tie during tying buffer" and "bond escalation over"
    vm.warp(_disputeCreatedAt);

    // Pledge second time for dispute
    _bondEscalationModule.pledgeForDispute(mockRequest, mockDispute);

    // Pledge revert if the maximum number of escalations is reached
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_MaxNumberOfEscalationsReached.selector);
    _bondEscalationModule.pledgeForDispute(mockRequest, mockDispute);

    // Get the bond escalation
    _bondEscalation = _bondEscalationModule.getEscalation(_requestId);

    // Check that the pledge was registered
    uint256 _pledgesForDispute = _bondEscalationModule.pledgesForDispute(_requestId, disputer);
    assertEq(_pledgesForDispute, 2);
    assertEq(_bondEscalation.amountOfPledgesForDispute, 2);

    // Calculate the amount to pay
    uint256 _amountToPay = _pledgeSize + (_pledgeSize / 2);

    // Settle bond escalation reverts if bond escalation is not over
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationNotOver.selector);
    _bondEscalationModule.settleBondEscalation(mockRequest, mockResponse, mockDispute);

    // Warp to pass the escalation deadline
    vm.warp(_disputeCreatedAt + _expectedDeadline + _tyingBuffer + 1);

    // The bond escalation accounting should have been called to settle the bond escalation
    vm.expectCall(
      address(_bondEscalationAccounting),
      abi.encodeCall(
        IBondEscalationAccounting.onSettleBondEscalation,
        (mockRequest, mockDispute, usdc, _amountToPay, _pledgesForDispute)
      )
    );

    // The bond escalation accounting should have been called to pay the proposer
    vm.expectCall(
      address(_bondEscalationAccounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, proposer, disputer, usdc, _pledgeSize))
    );

    // The bond escalation accounting should have been called to release the proposer's bond
    vm.expectCall(
      address(_bondEscalationAccounting),
      abi.encodeCall(IAccountingExtension.release, (disputer, _requestId, usdc, _pledgeSize))
    );

    // Escalate dispute should won the dispute
    _bondEscalationModule.settleBondEscalation(mockRequest, mockResponse, mockDispute);

    //The oracle should have been called to finalize the dispute
    assertTrue(IOracle.DisputeStatus.Won == oracle.disputeStatus(_disputeId));

    // //The new bond escalation should have the status DisputerWon
    _bondEscalation = _bondEscalationModule.getEscalation(_requestId);
    assertTrue(_bondEscalation.status == IBondEscalationModule.BondEscalationStatus.DisputerWon);
  }

  function test_disputeLostDispute() public {
    mockDispute.requestId = _requestId;

    // Bond escalation should call pledge
    vm.expectCall(
      address(_bondEscalationAccounting),
      abi.encodeCall(IBondEscalationAccounting.pledge, (proposer, mockRequest, mockDispute, usdc, _pledgeSize))
    );

    // Pledge for dispute
    _deposit(_bondEscalationAccounting, proposer, usdc, _pledgeSize * 3);
    vm.startPrank(proposer);
    _bondEscalationModule.pledgeAgainstDispute(mockRequest, mockDispute);

    // Pledge revert if can be only surpassed by 1
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_CanOnlySurpassByOnePledge.selector);
    _bondEscalationModule.pledgeAgainstDispute(mockRequest, mockDispute);
    vm.stopPrank();

    // Bond escalation should call pledge
    vm.expectCall(
      address(_bondEscalationAccounting),
      abi.encodeCall(IBondEscalationAccounting.pledge, (disputer, mockRequest, mockDispute, usdc, _pledgeSize))
    );

    // Pledge for dispute
    _deposit(_bondEscalationAccounting, disputer, usdc, _pledgeSize);
    vm.prank(disputer);
    _bondEscalationModule.pledgeForDispute(mockRequest, mockDispute);

    // Get the bond escalation
    IBondEscalationModule.BondEscalation memory _bondEscalation = _bondEscalationModule.getEscalation(_requestId);

    // Check that the pledge was registered
    assertEq(_bondEscalationModule.pledgesForDispute(_requestId, disputer), 1);
    assertEq(_bondEscalation.amountOfPledgesForDispute, 1);

    // Pledge revert if the maximum number of escalations is reached
    vm.startPrank(proposer);
    _bondEscalationModule.pledgeAgainstDispute(mockRequest, mockDispute);
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_MaxNumberOfEscalationsReached.selector);
    _bondEscalationModule.pledgeAgainstDispute(mockRequest, mockDispute);

    // Get the bond escalation
    _bondEscalation = _bondEscalationModule.getEscalation(_requestId);

    // Check that the pledge was registered
    uint256 _pledgesAgainstDispute = _bondEscalationModule.pledgesAgainstDispute(_requestId, proposer);
    assertEq(_pledgesAgainstDispute, 2);
    assertEq(_bondEscalation.amountOfPledgesAgainstDispute, 2);

    // Calculate the amount to pay
    uint256 _amountToPay = _pledgeSize + (_pledgeSize / 2);

    // Settle bond escalation reverts if bond escalation is not over
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationNotOver.selector);
    _bondEscalationModule.settleBondEscalation(mockRequest, mockResponse, mockDispute);

    // Warp to pass the escalation deadline
    vm.warp(_disputeCreatedAt + _expectedResponseDeadline + 1);

    // The bond escalation accounting should have been called to settle the bond escalation
    vm.expectCall(
      address(_bondEscalationAccounting),
      abi.encodeCall(
        IBondEscalationAccounting.onSettleBondEscalation,
        (mockRequest, mockDispute, usdc, _amountToPay, _pledgesAgainstDispute)
      )
    );

    // The bond escalation accounting should have been called to pay the proposer
    vm.expectCall(
      address(_bondEscalationAccounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, disputer, proposer, usdc, _pledgeSize))
    );

    // The bond escalation accounting should not have been called to release the proposer's bond
    vm.expectCall(
      address(_bondEscalationAccounting),
      abi.encodeCall(IAccountingExtension.release, (disputer, _requestId, usdc, _pledgeSize)),
      0
    );

    // Escalate dispute should won the dispute
    _bondEscalationModule.settleBondEscalation(mockRequest, mockResponse, mockDispute);

    //The oracle should have been called to finalize the dispute
    assertTrue(IOracle.DisputeStatus.Lost == oracle.disputeStatus(_disputeId));

    // //The new bond escalation should have the status DisputerLost
    _bondEscalation = _bondEscalationModule.getEscalation(_requestId);
    assertTrue(_bondEscalation.status == IBondEscalationModule.BondEscalationStatus.DisputerLost);
  }

  function test_escalateDisputeArbitratorResolveNoResolution() public {
    // Escalate dispute reverts if dispute does not exist
    mockDispute.requestId = bytes32(0);
    vm.expectRevert(ValidatorLib.ValidatorLib_InvalidDisputeBody.selector);
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

    mockDispute.requestId = _requestId;

    // Escalate dispute reverts if escalation is not over
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationNotOver.selector);
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

    // Check that the dispute is active
    assertTrue(
      _bondEscalationModule.getEscalation(_requestId).status == IBondEscalationModule.BondEscalationStatus.Active
    );

    // Pledge for dispute
    _deposit(_bondEscalationAccounting, disputer, usdc, _pledgeSize);
    vm.prank(disputer);
    _bondEscalationModule.pledgeForDispute(mockRequest, mockDispute);

    // Warp blocks to pass the escalation deadline
    vm.warp(_disputeCreatedAt + _expectedResponseDeadline + 1);

    // Escalate dispute reverts if dispute is not escalatable
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_NotEscalatable.selector);
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

    // Roll back the timestamp because we need to simulate the custom error "not escalatable"
    vm.warp(_disputeCreatedAt);

    // Pledge against dispute
    _deposit(_bondEscalationAccounting, proposer, usdc, _pledgeSize);
    vm.prank(proposer);
    _bondEscalationModule.pledgeAgainstDispute(mockRequest, mockDispute);

    // Warp blocks to pass the escalation deadline
    vm.warp(_disputeCreatedAt + _expectedDeadline + _tyingBuffer + 1);

    // Settle bond escalation reverts if dispute is not escalated
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_ShouldBeEscalated.selector);
    _bondEscalationModule.settleBondEscalation(mockRequest, mockResponse, mockDispute);

    // Create bond escalation
    IBondEscalationModule.BondEscalation memory _bondEscalation;

    // The oracle should call the dispute module
    vm.expectCall(
      address(_bondEscalationModule),
      abi.encodeCall(IDisputeModule.onDisputeStatusChange, (_disputeId, mockRequest, mockResponse, mockDispute))
    );

    // The oracle should call startResolution in the resolution module
    vm.expectCall(
      address(_arbitratorModule),
      abi.encodeCall(IResolutionModule.startResolution, (_disputeId, mockRequest, mockResponse, mockDispute))
    );

    // The arbitrator module should call the arbitrator
    vm.expectCall(
      address(_mockArbitrator), abi.encodeCall(MockArbitrator.resolve, (mockRequest, mockResponse, mockDispute))
    );

    // We escalate the dispute
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

    // We check that the dispute was escalated
    IOracle.DisputeStatus _disputeStatus = oracle.disputeStatus(_disputeId);
    assertTrue(_disputeStatus == IOracle.DisputeStatus.Escalated);

    // The BondEscalationModule should now have the escalation status escalated
    _bondEscalation = _bondEscalationModule.getEscalation(_requestId);
    assertTrue(_bondEscalation.status == IBondEscalationModule.BondEscalationStatus.Escalated);

    // The ArbitratorModule should have updated the status of the dispute
    assertTrue(_arbitratorModule.getStatus(_disputeId) == IArbitratorModule.ArbitrationStatus.Active);

    // Escalate dispute reverts if dispute is not active
    vm.expectRevert(abi.encodeWithSelector(IOracle.Oracle_CannotEscalate.selector, _disputeId));
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

    // Revert if bond escalation cant be settled
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_BondEscalationCantBeSettled.selector);
    _bondEscalationModule.settleBondEscalation(mockRequest, mockResponse, mockDispute);

    // The bond escalation accounting should have been called to release the proposer's bond
    vm.expectCall(
      address(_bondEscalationAccounting),
      abi.encodeCall(
        IAccountingExtension.release, (mockDispute.disputer, mockDispute.requestId, usdc, _expectedBondSize)
      )
    );

    // Resolve the dispute escalated with no resolution
    _mockArbitrator.setAnswer(IOracle.DisputeStatus.NoResolution);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);

    // The arbitrator module should have updated the status of the dispute
    assertTrue(_arbitratorModule.getStatus(_disputeId) == IArbitratorModule.ArbitrationStatus.Resolved);

    // The BondEscalationModule should have updated the status of the escalation
    assertTrue(
      _bondEscalationModule.getEscalation(_requestId).status == IBondEscalationModule.BondEscalationStatus.Escalated
    );

    // Oracle should have updated the status of the dispute
    assertTrue(oracle.disputeStatus(_disputeId) == IOracle.DisputeStatus.NoResolution);

    // Propose a new response and dispute it
    _deposit(_bondEscalationAccounting, proposer, usdc, _expectedBondSize);
    mockResponse.response = bytes('new response');
    vm.prank(proposer);
    oracle.proposeResponse(mockRequest, mockResponse);

    // Get the new response id
    mockDispute.responseId = _getId(mockResponse);

    // The oracle should call the dispute module with the new dispute id
    bytes32 _newDisputeId = _getId(mockDispute);

    // The oracle should call the dispute module
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.escalateDispute, (mockRequest, mockResponse, mockDispute)));

    vm.expectCall(
      address(_bondEscalationModule),
      abi.encodeCall(IDisputeModule.onDisputeStatusChange, (_newDisputeId, mockRequest, mockResponse, mockDispute))
    );

    _deposit(_bondEscalationAccounting, disputer, usdc, _expectedBondSize);
    vm.prank(disputer);
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);

    // We check that the dispute was escalated
    _disputeStatus = oracle.disputeStatus(_newDisputeId);
    assertTrue(_disputeStatus == IOracle.DisputeStatus.Escalated);

    // The BondEscalationModule should now have the escalation status escalated
    _bondEscalation = _bondEscalationModule.getEscalation(_requestId);
    assertTrue(_bondEscalation.status == IBondEscalationModule.BondEscalationStatus.Escalated);
  }

  function test_escalateDisputeArbitratorResolveLost() public {
    mockDispute.requestId = _requestId;

    // The oracle should call the dispute module
    vm.expectCall(
      address(_bondEscalationModule),
      abi.encodeCall(IDisputeModule.onDisputeStatusChange, (_disputeId, mockRequest, mockResponse, mockDispute))
    );

    // The oracle should call startResolution in the resolution module
    vm.expectCall(
      address(_arbitratorModule),
      abi.encodeCall(IResolutionModule.startResolution, (_disputeId, mockRequest, mockResponse, mockDispute))
    );

    // The arbitrator module should call the arbitrator
    vm.expectCall(
      address(_mockArbitrator), abi.encodeCall(MockArbitrator.resolve, (mockRequest, mockResponse, mockDispute))
    );

    // We escalate the dispute
    vm.warp(_disputeCreatedAt + _expectedDeadline + 1);
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

    // We check that the dispute was escalated
    IOracle.DisputeStatus _disputeStatus = oracle.disputeStatus(_disputeId);
    assertTrue(_disputeStatus == IOracle.DisputeStatus.Escalated);

    // The BondEscalationModule should now have the escalation status escalated
    IBondEscalationModule.BondEscalation memory _bondEscalation = _bondEscalationModule.getEscalation(_requestId);
    assertTrue(_bondEscalation.status == IBondEscalationModule.BondEscalationStatus.Escalated);

    // The ArbitratorModule should have updated the status of the dispute
    assertTrue(_arbitratorModule.getStatus(_disputeId) == IArbitratorModule.ArbitrationStatus.Active);

    // The bond escalation accounting should have been called to pay the proposer
    vm.expectCall(
      address(_bondEscalationAccounting),
      abi.encodeCall(
        IAccountingExtension.pay, (_requestId, mockDispute.disputer, mockResponse.proposer, usdc, _expectedBondSize)
      )
    );

    // Resolve the dispute escalated with no resolution
    _mockArbitrator.setAnswer(IOracle.DisputeStatus.Lost);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);

    // The arbitrator module should have updated the status of the dispute
    assertTrue(_arbitratorModule.getStatus(_disputeId) == IArbitratorModule.ArbitrationStatus.Resolved);

    // The BondEscalationModule should have updated the status of the escalation
    assertTrue(
      _bondEscalationModule.getEscalation(_requestId).status == IBondEscalationModule.BondEscalationStatus.DisputerLost
    );

    // Oracle should have updated the status of the dispute
    assertTrue(oracle.disputeStatus(_disputeId) == IOracle.DisputeStatus.Lost);
  }

  function test_escalateDisputeArbitratorResolveWon() public {
    mockDispute.requestId = _requestId;

    // The oracle should call the dispute module
    vm.expectCall(
      address(_bondEscalationModule),
      abi.encodeCall(IDisputeModule.onDisputeStatusChange, (_disputeId, mockRequest, mockResponse, mockDispute))
    );

    // The oracle should call startResolution in the resolution module
    vm.expectCall(
      address(_arbitratorModule),
      abi.encodeCall(IResolutionModule.startResolution, (_disputeId, mockRequest, mockResponse, mockDispute))
    );

    // The arbitrator module should call the arbitrator
    vm.expectCall(
      address(_mockArbitrator), abi.encodeCall(MockArbitrator.resolve, (mockRequest, mockResponse, mockDispute))
    );

    // We escalate the dispute
    vm.warp(_disputeCreatedAt + _expectedDeadline + 1);
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

    // We check that the dispute was escalated
    IOracle.DisputeStatus _disputeStatus = oracle.disputeStatus(_disputeId);
    assertTrue(_disputeStatus == IOracle.DisputeStatus.Escalated);

    // The BondEscalationModule should now have the escalation status escalated
    IBondEscalationModule.BondEscalation memory _bondEscalation = _bondEscalationModule.getEscalation(_requestId);
    assertTrue(_bondEscalation.status == IBondEscalationModule.BondEscalationStatus.Escalated);

    // The ArbitratorModule should have updated the status of the dispute
    assertTrue(_arbitratorModule.getStatus(_disputeId) == IArbitratorModule.ArbitrationStatus.Active);

    // The bond escalation accounting should have been called to pay the disputer
    vm.expectCall(
      address(_bondEscalationAccounting),
      abi.encodeCall(
        IAccountingExtension.pay, (_requestId, mockResponse.proposer, mockDispute.disputer, usdc, _expectedBondSize)
      )
    );

    // The bond escalation accounting should have been called to release the proposer's bond
    vm.expectCall(
      address(_bondEscalationAccounting),
      abi.encodeCall(
        IAccountingExtension.release, (mockDispute.disputer, mockDispute.requestId, usdc, _expectedBondSize)
      )
    );

    // Resolve the dispute escalated with no resolution
    _mockArbitrator.setAnswer(IOracle.DisputeStatus.Won);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);

    // The arbitrator module should have updated the status of the dispute
    assertTrue(_arbitratorModule.getStatus(_disputeId) == IArbitratorModule.ArbitrationStatus.Resolved);

    // The BondEscalationModule should have updated the status of the escalation
    assertTrue(
      _bondEscalationModule.getEscalation(_requestId).status == IBondEscalationModule.BondEscalationStatus.DisputerWon
    );

    // Oracle should have updated the status of the dispute
    assertTrue(oracle.disputeStatus(_disputeId) == IOracle.DisputeStatus.Won);
  }
}
