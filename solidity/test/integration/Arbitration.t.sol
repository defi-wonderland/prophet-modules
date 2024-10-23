// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_Arbitration is IntegrationBase {
  MockAtomicArbitrator internal _mockAtomicArbitrator;

  function setUp() public override {
    super.setUp();

    vm.prank(governance);
    _mockAtomicArbitrator = new MockAtomicArbitrator(oracle);

    _deposit(_accountingExtension, requester, usdc, _expectedReward);
    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);
    _deposit(_accountingExtension, disputer, usdc, _expectedBondSize);
  }

  function test_resolveCorrectDispute_twoStep() public {
    bytes32 _disputeId = _setupDispute(address(_mockArbitrator));

    // Check: is the dispute status unknown before starting the resolution?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Unknown));

    // First step: escalating the dispute
    vm.prank(disputer);
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute, _createAccessControl(disputer));

    // Check: is the dispute status active after starting the resolution?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Active));

    // Second step: resolving the dispute
    vm.prank(disputer);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute, _createAccessControl(disputer));

    // Check: is the dispute status resolved after calling resolve?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Resolved));

    IOracle.DisputeStatus _disputeStatus = oracle.disputeStatus(_disputeId);
    // Check: is the dispute updated as won?
    assertEq(uint256(_disputeStatus), uint256(IOracle.DisputeStatus.Won));

    // Check: does the disputer receive the proposer's bond?
    uint256 _disputerBalance = _accountingExtension.balanceOf(disputer, usdc);
    assertEq(_disputerBalance, _expectedBondSize * 2);

    // Check: does the proposer get its bond slashed?
    uint256 _proposerBondedAmount = _accountingExtension.bondedAmountOf(proposer, usdc, _getId(mockRequest));
    assertEq(_proposerBondedAmount, 0);
  }

  function test_resolveCorrectDispute_atomically() public {
    bytes32 _disputeId = _setupDispute(address(_mockAtomicArbitrator));

    // Check: is the dispute status unknown before starting the resolution?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Unknown));

    // First step: escalating the dispute
    vm.prank(disputer);
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute, _createAccessControl(disputer));

    // Check: is the dispute status resolved after calling resolve?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Resolved));

    IOracle.DisputeStatus _disputeStatus = oracle.disputeStatus(_disputeId);
    // Check: is the dispute updated as won?
    assertEq(uint256(_disputeStatus), uint256(IOracle.DisputeStatus.Won));

    // Check: does the disputer receive the proposer's bond?
    uint256 _disputerBalance = _accountingExtension.balanceOf(disputer, usdc);
    assertEq(_disputerBalance, _expectedBondSize * 2);

    // Check: does the proposer get its bond slashed?
    uint256 _proposerBondedAmount = _accountingExtension.bondedAmountOf(proposer, usdc, _getId(mockRequest));
    assertEq(_proposerBondedAmount, 0);
  }

  function test_resolveIncorrectDispute_twoStep() public {
    bytes32 _disputeId = _setupDispute(address(_mockArbitrator));
    // Check: is the dispute status unknown before starting the resolution?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Unknown));

    // First step: escalating the dispute
    vm.prank(disputer);
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute, _createAccessControl(disputer));

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
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute, _createAccessControl(disputer));

    // Check: is the dispute status resolved after calling resolve?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Resolved));

    IOracle.DisputeStatus _disputeStatus = oracle.disputeStatus(_disputeId);
    // Check: is the dispute updated as lost?
    assertEq(uint256(_disputeStatus), uint256(IOracle.DisputeStatus.Lost));

    // Check: does the disputer receive the disputer's bond?
    uint256 _proposerBalance = _accountingExtension.balanceOf(proposer, usdc);
    assertEq(_proposerBalance, _expectedBondSize * 2);

    // Check: does the disputer get its bond slashed?
    uint256 _disputerBondedAmount = _accountingExtension.bondedAmountOf(disputer, usdc, _getId(mockRequest));
    assertEq(_disputerBondedAmount, 0);
  }

  function test_resolveIncorrectDispute_atomically() public {
    bytes32 _disputeId = _setupDispute(address(_mockAtomicArbitrator));

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
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute, _createAccessControl(disputer));

    // Check: is the dispute status resolved after calling escalate?
    assertEq(uint256(_arbitratorModule.getStatus(_disputeId)), uint256(IArbitratorModule.ArbitrationStatus.Resolved));

    IOracle.DisputeStatus _disputeStatus = oracle.disputeStatus(_disputeId);
    // Check: is the dispute updated as lost?
    assertEq(uint256(_disputeStatus), uint256(IOracle.DisputeStatus.Lost));

    // Check: does the disputer receive the disputer's bond?
    uint256 _proposerBalance = _accountingExtension.balanceOf(proposer, usdc);
    assertEq(_proposerBalance, _expectedBondSize * 2);

    // Check: does the disputer get its bond slashed?
    uint256 _disputerBondedAmount = _accountingExtension.bondedAmountOf(disputer, usdc, _getId(mockRequest));
    assertEq(_disputerBondedAmount, 0);
  }

  function _setArbitrator(address _arbitrator) internal {
    mockRequest.resolutionModuleData = abi.encode(IArbitratorModule.RequestParameters({arbitrator: _arbitrator}));
  }

  function _setupDispute(address _arbitrator) internal returns (bytes32 _disputeId) {
    _setArbitrator(_arbitrator);
    _resetMockIds();

    _createRequest();
    _proposeResponse();
    _disputeId = _disputeResponse();
  }
}
