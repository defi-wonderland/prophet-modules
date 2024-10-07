// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_EscalateDispute is IntegrationBase {
  bytes32 internal _requestId;
  bytes32 internal _disputeId;
  uint256 internal _pledgeSize = _expectedBondSize;

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
        deadline: _expectedDeadline * 2,
        disputeWindow: _baseDisputeWindow
      })
    );

    mockRequest.disputeModuleData = abi.encode(
      IBondEscalationModule.RequestParameters({
        accountingExtension: _bondEscalationAccounting,
        bondToken: usdc,
        bondSize: _expectedBondSize,
        maxNumberOfEscalations: 1,
        bondEscalationDeadline: _expectedDeadline,
        tyingBuffer: 0,
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
  }

  function test_escalateDisputeResolveNoResolution() public {
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

    // Mine blocks to pass the escalation deadline
    _mineBlocks(_blocksDeadline + 1);

    // Escalate dispute reverts if dispute is not escalatable
    vm.expectRevert(IBondEscalationModule.BondEscalationModule_NotEscalatable.selector);
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

    // Roll back the blocks
    vm.warp(block.timestamp - (_blocksDeadline + 1) * BLOCK_TIME);

    // Pledge against dispute
    _deposit(_bondEscalationAccounting, proposer, usdc, _pledgeSize);
    vm.prank(proposer);
    _bondEscalationModule.pledgeAgainstDispute(mockRequest, mockDispute);

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
    _mineBlocks(_blocksDeadline + 1);
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

    // We check that the dispute was escalated
    IOracle.DisputeStatus _disputeStatus = oracle.disputeStatus(_disputeId);
    assertTrue(_disputeStatus == IOracle.DisputeStatus.Escalated);

    // The BondEscalationModule should now have the escalation status escalated
    IBondEscalationModule.BondEscalation memory _bondEscalation = _bondEscalationModule.getEscalation(_requestId);
    assertTrue(_bondEscalation.status == IBondEscalationModule.BondEscalationStatus.Escalated);

    // The ArbitratorModule should have updated the status of the dispute
    assertTrue(_arbitratorModule.getStatus(_disputeId) == IArbitratorModule.ArbitrationStatus.Active);

    // Escalate dispute reverts if dispute is not active
    vm.expectRevert(abi.encodeWithSelector(IOracle.Oracle_CannotEscalate.selector, _disputeId));
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

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

  function test_escalateDisputeResolveLost() public {
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
    _mineBlocks(_blocksDeadline + 1);
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

  function test_escalateDisputeResolveWon() public {
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
    _mineBlocks(_blocksDeadline + 1);
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
