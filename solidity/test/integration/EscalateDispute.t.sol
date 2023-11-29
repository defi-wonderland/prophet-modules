// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_EscalateDispute is IntegrationBase {
  bytes internal _responseData = abi.encode('response');

  uint256 internal _blocksDeadline = 600;

  IOracle.Request internal _request;
  IOracle.Response internal _response;
  IOracle.Dispute internal _dispute;
  bytes32 _requestId;
  bytes32 _responseId;
  bytes32 _disputeId;

  function setUp() public override {
    super.setUp();
    _expectedDeadline = block.timestamp + BLOCK_TIME * _blocksDeadline;
  }

  function test_escalateDispute() public {
    /// Create a dispute with bond escalation module and arbitrator module
    _createRequestAndDispute(
      _bondEscalationAccounting,
      _bondEscalationModule,
      abi.encode(
        IBondEscalationModule.RequestParameters({
          accountingExtension: _bondEscalationAccounting,
          bondToken: IERC20(USDC_ADDRESS),
          bondSize: _expectedBondSize,
          maxNumberOfEscalations: 1,
          bondEscalationDeadline: _expectedDeadline,
          tyingBuffer: 0,
          disputeWindow: 0
        })
      ),
      _arbitratorModule,
      abi.encode(_mockArbitrator)
    );

    /// Escalate dispute reverts if dispute does not exist
    _dispute.requestId = bytes32(0);
    vm.expectRevert(IOracle.Oracle_InvalidDisputeBody.selector);
    oracle.escalateDispute(_request, _response, _dispute);

    _dispute.requestId = _requestId;

    /// The oracle should call the dispute module
    vm.expectCall(
      address(_bondEscalationModule),
      abi.encodeCall(IDisputeModule.onDisputeStatusChange, (_disputeId, _request, _response, _dispute))
    );

    /// The oracle should call startResolution in the resolution module
    vm.expectCall(
      address(_arbitratorModule),
      abi.encodeCall(IResolutionModule.startResolution, (_disputeId, _request, _response, _dispute))
    );

    /// The arbitrator module should call the arbitrator
    vm.expectCall(address(_mockArbitrator), abi.encodeCall(MockArbitrator.resolve, (_request, _response, _dispute)));

    /// We escalate the dispute
    _mineBlocks(_blocksDeadline + 1);
    oracle.escalateDispute(_request, _response, _dispute);

    /// We check that the dispute was escalated
    IOracle.DisputeStatus _disputeStatus = oracle.disputeStatus(_disputeId);
    assertTrue(_disputeStatus == IOracle.DisputeStatus.Escalated);

    /// The BondEscalationModule should now have the escalation status escalated
    IBondEscalationModule.BondEscalation memory _bondEscalation = _bondEscalationModule.getEscalation(_requestId);
    assertTrue(_bondEscalation.status == IBondEscalationModule.BondEscalationStatus.Escalated);

    /// The ArbitratorModule should have updated the status of the dispute
    assertTrue(_arbitratorModule.getStatus(_disputeId) == IArbitratorModule.ArbitrationStatus.Active);

    /// Escalate dispute reverts if dispute is not active
    vm.expectRevert(abi.encodeWithSelector(IOracle.Oracle_CannotEscalate.selector, _disputeId));
    oracle.escalateDispute(_request, _response, _dispute);
  }

  function _createRequestAndDispute(
    IAccountingExtension _accounting,
    IDisputeModule _disputeModule,
    bytes memory _disputeModuleData,
    IResolutionModule _resolutionModule,
    bytes memory _resolutionModuleData
  ) internal {
    _forBondDepositERC20(_accounting, requester, usdc, _expectedBondSize, _expectedBondSize);

    _request = IOracle.Request({
      nonce: 0,
      requester: requester,
      requestModuleData: abi.encode(
        IHttpRequestModule.RequestParameters({
          url: _expectedUrl,
          method: _expectedMethod,
          body: _expectedBody,
          accountingExtension: _accounting,
          paymentToken: IERC20(USDC_ADDRESS),
          paymentAmount: _expectedReward
        })
        ),
      responseModuleData: abi.encode(
        IBondedResponseModule.RequestParameters({
          accountingExtension: _accounting,
          bondToken: IERC20(USDC_ADDRESS),
          bondSize: _expectedBondSize,
          deadline: _expectedDeadline,
          disputeWindow: _baseDisputeWindow
        })
        ),
      disputeModuleData: _disputeModuleData,
      resolutionModuleData: _resolutionModuleData,
      finalityModuleData: abi.encode(
        ICallbackModule.RequestParameters({target: address(_mockCallback), data: abi.encode(_expectedCallbackValue)})
        ),
      requestModule: address(_requestModule),
      responseModule: address(_responseModule),
      disputeModule: address(_disputeModule),
      resolutionModule: address(_resolutionModule),
      finalityModule: address(_callbackModule)
    });

    vm.startPrank(requester);
    _accounting.approveModule(address(_requestModule));
    _requestId = oracle.createRequest(_request, _ipfsHash);
    vm.stopPrank();

    _response = IOracle.Response({proposer: proposer, requestId: _requestId, response: _responseData});

    _forBondDepositERC20(_accounting, proposer, usdc, _expectedBondSize, _expectedBondSize);
    vm.startPrank(proposer);
    _accounting.approveModule(address(_responseModule));
    _responseId = oracle.proposeResponse(_request, _response);
    vm.stopPrank();

    _dispute = IOracle.Dispute({disputer: disputer, proposer: proposer, responseId: _responseId, requestId: _requestId});

    _forBondDepositERC20(_accounting, disputer, usdc, _expectedBondSize, _expectedBondSize);
    vm.startPrank(disputer);
    _accounting.approveModule(address(_disputeModule));
    _disputeId = oracle.disputeResponse(_request, _response, _dispute);
    vm.stopPrank();
  }
}
