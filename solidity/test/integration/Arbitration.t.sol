// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';
import {IArbitrator} from '../../interfaces/IArbitrator.sol';
import {MockAtomicArbitrator} from '../mocks/MockAtomicArbitrator.sol';

contract Integration_Arbitration is IntegrationBase {
  MockAtomicArbitrator internal _mockAtomicArbitrator;
  IOracle.Request internal _request;
  IOracle.Response internal _response;
  IOracle.Dispute internal _dispute;

  bytes32 _requestId;
  bytes32 _responseId;
  bytes32 _disputeId;

  function setUp() public override {
    super.setUp();

    vm.prank(governance);
    _mockAtomicArbitrator = new MockAtomicArbitrator(oracle);

    _expectedDeadline = block.timestamp + BLOCK_TIME * 600;

    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedBondSize, _expectedBondSize);
    _forBondDepositERC20(_accountingExtension, proposer, usdc, _expectedBondSize, _expectedBondSize);
    _forBondDepositERC20(_accountingExtension, disputer, usdc, _expectedBondSize, _expectedBondSize);
  }

  function test_resolveCorrectDispute_twoStep() public {
    _setupDispute(address(_mockArbitrator));
    // Check: is the dispute status unknown before starting the resolution?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Unknown));

    // First step: escalating the dispute
    vm.prank(disputer);
    oracle.escalateDispute(_request, _response, _dispute);

    // Check: is the dispute status active after starting the resolution?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Active));

    // Second step: resolving the dispute
    vm.prank(disputer);
    oracle.resolveDispute(_request, _response, _dispute);

    // Check: is the dispute status resolved after calling resolve?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Resolved));

    IOracle.DisputeStatus _disputeStatus = oracle.disputeStatus(_disputeId);
    // Check: is the dispute updated as won?
    assertEq(uint256(_disputeStatus), uint256(IOracle.DisputeStatus.Won));

    // Check: does the disputer receive the proposer's bond?
    uint256 _disputerBalance = _accountingExtension.balanceOf(disputer, usdc);
    assertEq(_disputerBalance, _expectedBondSize * 2);

    // Check: does the proposer get its bond slashed?
    uint256 _proposerBondedAmount = _accountingExtension.bondedAmountOf(proposer, usdc, _requestId);
    assertEq(_proposerBondedAmount, 0);
  }

  function test_resolveCorrectDispute_atomically() public {
    _setupDispute(address(_mockAtomicArbitrator));

    // Check: is the dispute status unknown before starting the resolution?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Unknown));

    // First step: escalating the dispute
    vm.prank(disputer);
    oracle.escalateDispute(_request, _response, _dispute);

    // Check: is the dispute status resolved after calling resolve?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Resolved));

    IOracle.DisputeStatus _disputeStatus = oracle.disputeStatus(_disputeId);
    // Check: is the dispute updated as won?
    assertEq(uint256(_disputeStatus), uint256(IOracle.DisputeStatus.Won));

    // Check: does the disputer receive the proposer's bond?
    uint256 _disputerBalance = _accountingExtension.balanceOf(disputer, usdc);
    assertEq(_disputerBalance, _expectedBondSize * 2);

    // Check: does the proposer get its bond slashed?
    uint256 _proposerBondedAmount = _accountingExtension.bondedAmountOf(proposer, usdc, _requestId);
    assertEq(_proposerBondedAmount, 0);
  }

  function test_resolveIncorrectDispute_twoStep() public {
    _setupDispute(address(_mockArbitrator));
    // Check: is the dispute status unknown before starting the resolution?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Unknown));

    // First step: escalating the dispute
    vm.prank(disputer);
    oracle.escalateDispute(_request, _response, _dispute);

    // Check: is the dispute status active after starting the resolution?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Active));

    // Mocking the answer to return false ==> dispute lost
    vm.mockCall(
      address(_mockArbitrator),
      abi.encodeCall(IArbitrator.getAnswer, (_disputeId)),
      abi.encode(IOracle.DisputeStatus.Lost)
    );

    // Second step: resolving the dispute
    vm.prank(disputer);
    oracle.resolveDispute(_request, _response, _dispute);

    // Check: is the dispute status resolved after calling resolve?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Resolved));

    IOracle.DisputeStatus _disputeStatus = oracle.disputeStatus(_disputeId);
    // Check: is the dispute updated as lost?
    assertEq(uint256(_disputeStatus), uint256(IOracle.DisputeStatus.Lost));

    // Check: does the disputer receive the disputer's bond?
    uint256 _proposerBalance = _accountingExtension.balanceOf(proposer, usdc);
    assertEq(_proposerBalance, _expectedBondSize * 2);

    // Check: does the disputer get its bond slashed?
    uint256 _disputerBondedAmount = _accountingExtension.bondedAmountOf(disputer, usdc, _requestId);
    assertEq(_disputerBondedAmount, 0);
  }

  function test_resolveIncorrectDispute_atomically() public {
    _setupDispute(address(_mockAtomicArbitrator));

    // Check: is the dispute status unknown before starting the resolution?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Unknown));

    // Mocking the answer to return false ==> dispute lost
    vm.mockCall(
      address(_mockAtomicArbitrator),
      abi.encodeCall(IArbitrator.getAnswer, (_disputeId)),
      abi.encode(IOracle.DisputeStatus.Lost)
    );

    // First step: escalating and resolving the dispute
    vm.prank(disputer);
    oracle.escalateDispute(_request, _response, _dispute);

    // Check: is the dispute status resolved after calling escalate?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Resolved));

    IOracle.DisputeStatus _disputeStatus = oracle.disputeStatus(_disputeId);
    // Check: is the dispute updated as lost?
    assertEq(uint256(_disputeStatus), uint256(IOracle.DisputeStatus.Lost));

    // Check: does the disputer receive the disputer's bond?
    uint256 _proposerBalance = _accountingExtension.balanceOf(proposer, usdc);
    assertEq(_proposerBalance, _expectedBondSize * 2);

    // Check: does the disputer get its bond slashed?
    uint256 _disputerBondedAmount = _accountingExtension.bondedAmountOf(disputer, usdc, _requestId);
    assertEq(_disputerBondedAmount, 0);
  }

  function _setupDispute(address _arbitrator) internal {
    _request = IOracle.Request({
      nonce: 0,
      requester: requester,
      requestModuleData: abi.encode(
        IHttpRequestModule.RequestParameters({
          url: _expectedUrl,
          method: _expectedMethod,
          body: _expectedBody,
          accountingExtension: _accountingExtension,
          paymentToken: IERC20(USDC_ADDRESS),
          paymentAmount: _expectedReward
        })
        ),
      responseModuleData: abi.encode(
        IBondedResponseModule.RequestParameters({
          accountingExtension: _accountingExtension,
          bondToken: IERC20(USDC_ADDRESS),
          bondSize: _expectedBondSize,
          deadline: _expectedDeadline,
          disputeWindow: _baseDisputeWindow
        })
        ),
      disputeModuleData: abi.encode(
        IBondedDisputeModule.RequestParameters({
          accountingExtension: _accountingExtension,
          bondToken: IERC20(USDC_ADDRESS),
          bondSize: _expectedBondSize
        })
        ),
      resolutionModuleData: abi.encode(_arbitrator),
      finalityModuleData: abi.encode(
        ICallbackModule.RequestParameters({target: address(_mockCallback), data: abi.encode(_expectedCallbackValue)})
        ),
      requestModule: address(_requestModule),
      responseModule: address(_responseModule),
      disputeModule: address(_bondedDisputeModule),
      resolutionModule: address(_arbitratorModule),
      finalityModule: address(_callbackModule)
    });

    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    _requestId = oracle.createRequest(_request, _ipfsHash);
    vm.stopPrank();

    _response = IOracle.Response({proposer: proposer, requestId: _requestId, response: abi.encode('response')});

    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    _responseId = oracle.proposeResponse(_request, _response);
    vm.stopPrank();

    _dispute = IOracle.Dispute({proposer: proposer, disputer: disputer, requestId: _requestId, responseId: _responseId});

    vm.startPrank(disputer);
    _accountingExtension.approveModule(address(_bondedDisputeModule));
    _disputeId = oracle.disputeResponse(_request, _response, _dispute);
    vm.stopPrank();
  }
}
