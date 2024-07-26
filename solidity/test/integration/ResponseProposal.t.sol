// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_ResponseProposal is IntegrationBase {
  bytes32 internal _requestId;

  function setUp() public override {
    super.setUp();

    // Requester and proposer deposit funds
    _deposit(_accountingExtension, requester, usdc, _expectedReward);
    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);

    // Create the request
    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    _requestId = oracle.createRequest(mockRequest, _ipfsHash);
    vm.stopPrank();

    // Approve the response module on behalf of the proposer
    vm.prank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
  }

  /**
   * @notice Proposing a response updates the state of the oracle, including the list of participants and the response's creation time
   */
  function test_proposeResponse_validResponse(bytes memory _responseBytes) public {
    mockResponse.response = _responseBytes;

    vm.prank(proposer);
    oracle.proposeResponse(mockRequest, mockResponse);

    // Check: the proposer is a participant now?
    assertTrue(oracle.isParticipant(_requestId, proposer));

    // Check: the response id was added to the list?
    bytes32[] memory _getResponseIds = oracle.getResponseIds(_requestId);
    assertEq(_getResponseIds[0], _getId(mockResponse));

    // Check: the creation block is correct?
    assertEq(oracle.createdAt(_getId(mockResponse)), block.number);
  }

  /**
   * @notice Proposing a response after the deadline reverts
   */
  function test_proposeResponse_afterDeadline(uint256 _timestamp, bytes memory _responseBytes) public {
    vm.assume(_timestamp > _expectedDeadline);

    // Warp to timestamp after deadline
    vm.warp(_timestamp);

    mockResponse.response = _responseBytes;

    // Check: does revert if deadline is passed?
    vm.expectRevert(IBondedResponseModule.BondedResponseModule_TooLateToPropose.selector);

    vm.prank(proposer);
    oracle.proposeResponse(mockRequest, mockResponse);
  }

  /**
   * @notice Proposing a response to an already answered request reverts
   */
  function test_proposeResponse_alreadyResponded(bytes memory _responseBytes) public {
    mockResponse.response = _responseBytes;

    // First response
    vm.prank(proposer);
    oracle.proposeResponse(mockRequest, mockResponse);

    mockResponse.response = abi.encode('second response');

    // Check: does revert if already responded?
    vm.expectRevert(IBondedResponseModule.BondedResponseModule_AlreadyResponded.selector);

    // Second response
    vm.prank(proposer);
    oracle.proposeResponse(mockRequest, mockResponse);
  }

  /**
   * @notice Proposing a response with an invalid request id reverts
   */
  function test_proposeResponse_nonExistentRequest(bytes memory _responseBytes, bytes32 _nonExistentRequestId) public {
    vm.assume(_nonExistentRequestId != _requestId);

    mockResponse.response = _responseBytes;
    mockResponse.requestId = _nonExistentRequestId;

    // Check: does revert if request does not exist?
    vm.expectRevert(IOracle.Oracle_InvalidResponseBody.selector);

    vm.prank(proposer);
    oracle.proposeResponse(mockRequest, mockResponse);
  }

  /**
   * @notice Proposing without enough funds bonded reverts
   */
  function test_proposeResponse_insufficientFunds(bytes memory _responseBytes) public {
    // Using WETH as the bond token
    mockRequest.nonce += 1;
    mockRequest.responseModuleData = abi.encode(
      IBondedResponseModule.RequestParameters({
        accountingExtension: _accountingExtension,
        bondToken: weth,
        bondSize: _expectedBondSize,
        deadline: _expectedDeadline,
        disputeWindow: _baseDisputeWindow
      })
    );

    // Requester deposit funds
    _deposit(_accountingExtension, requester, usdc, _expectedReward);

    // Creates the request
    vm.prank(requester);
    oracle.createRequest(mockRequest, _ipfsHash);

    mockResponse.response = _responseBytes;
    _resetMockIds();

    // Check: does revert if proposer does not have enough funds bonded?
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);

    vm.prank(proposer);
    oracle.proposeResponse(mockRequest, mockResponse);
  }

  function test_proposeResponse_fromUnapprovedDisputeModule(bytes memory _responseBytes) public {
    address _attacker = makeAddr('attacker');
    mockRequest.nonce += 1;
    mockRequest.requester = _attacker;
    mockRequest.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _expectedUrl,
        body: _expectedBody,
        method: _expectedMethod,
        accountingExtension: _accountingExtension,
        paymentToken: usdc,
        paymentAmount: 0
      })
    );

    uint256 _oldProposerBalance = _accountingExtension.balanceOf(proposer, usdc);
    assertGt(_oldProposerBalance, 0);

    vm.startPrank(_attacker);
    // Attacker creates a request with their own address as the dispute module
    mockRequest.disputeModule = _attacker;
    _accountingExtension.approveModule(mockRequest.requestModule);
    bytes32 _requestIdAttacker = oracle.createRequest(mockRequest, _ipfsHash);

    // Attacker proposes a response from their address (the dispute module) and using another user as the proposer
    mockResponse.response = _responseBytes;
    mockResponse.proposer = proposer;
    mockResponse.requestId = _requestIdAttacker;

    oracle.proposeResponse(mockRequest, mockResponse);

    vm.stopPrank();

    uint256 _newProposerBalance = _accountingExtension.balanceOf(proposer, usdc);

    // Proposer got their balance bonded when they didn't create the response
    assertTrue(_expectedBondSize != 0);
    assertEq(_oldProposerBalance, _newProposerBalance + _expectedBondSize);
  }
}
