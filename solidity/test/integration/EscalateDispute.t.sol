// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_EscalateDispute is IntegrationBase {
  bytes32 internal _requestId;
  bytes32 internal _disputeId;

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
        deadline: _expectedDeadline,
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

    vm.startPrank(requester);
    _bondEscalationAccounting.approveModule(address(_requestModule));
    _requestId = oracle.createRequest(mockRequest, _ipfsHash);
    vm.stopPrank();

    _resetMockIds();

    // Propose a response and dispute it
    _deposit(_bondEscalationAccounting, proposer, usdc, _expectedBondSize);
    vm.startPrank(proposer);
    _bondEscalationAccounting.approveModule(address(_responseModule));
    oracle.proposeResponse(mockRequest, mockResponse, _createAccessControl(proposer));
    vm.stopPrank();

    _deposit(_bondEscalationAccounting, disputer, usdc, _expectedBondSize);
    vm.startPrank(disputer);
    _bondEscalationAccounting.approveModule(address(_bondEscalationModule));
    _disputeId = oracle.disputeResponse(mockRequest, mockResponse, mockDispute, _createAccessControl(disputer));
    vm.stopPrank();
  }

  function test_escalateDispute() public {
    address _escalator = makeAddr('escalator');
    // Escalate dispute reverts if dispute does not exist
    mockDispute.requestId = bytes32(0);
    vm.expectRevert(ValidatorLib.ValidatorLib_InvalidDisputeBody.selector);
    vm.prank(_escalator);
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute, _createAccessControl(_escalator));

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
      address(_mockArbitrator),
      abi.encodeCall(
        MockArbitrator.resolve,
        (mockRequest, mockResponse, mockDispute, _createAccessControl(address(_arbitratorModule)))
      )
    );

    // We escalate the dispute
    vm.warp(block.timestamp + _expectedDeadline + 1);
    vm.prank(_escalator);
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute, _createAccessControl(_escalator));

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
    vm.prank(_escalator);
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute, _createAccessControl(_escalator));
  }
}
