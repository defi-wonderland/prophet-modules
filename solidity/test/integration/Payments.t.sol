// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_Payments is IntegrationBase {
  function test_releaseValidResponse_ERC20(uint256 _rewardSize, uint256 _bondSize) public {
    // Exception to avoid overflow when depositing.
    vm.assume(_rewardSize < type(uint256).max - _bondSize);

    // Update the parameters of the request.
    _setupRequest(_bondSize, _rewardSize, usdc);

    // Requester bonds and creates a request.
    _deposit(_accountingExtension, requester, usdc, _rewardSize);
    bytes32 _requestId = _createRequest();

    // Proposer bonds and proposes a response.
    _deposit(_accountingExtension, proposer, usdc, _bondSize);
    _proposeResponse();

    // Check: requester has placed the bond?
    assertEq(_accountingExtension.bondedAmountOf(requester, usdc, _requestId), _rewardSize);

    // Check: proposer has placed the bond?
    assertEq(_accountingExtension.bondedAmountOf(proposer, usdc, _requestId), _bondSize);

    // Warp to finalization time.
    vm.warp(block.timestamp + _expectedDeadline + _baseDisputeWindow);

    // Finalize request/response
    oracle.finalize(mockRequest, mockResponse);

    // Check: requester has paid for response?
    assertEq(_accountingExtension.balanceOf(requester, usdc), 0);

    // Check: requester has no bonded balance left?
    assertEq(_accountingExtension.bondedAmountOf(requester, usdc, _requestId), 0);

    // Check: proposer got the reward?
    assertEq(_accountingExtension.balanceOf(proposer, usdc), _rewardSize + _bondSize);

    // Check: proposer has no bonded balance left?
    assertEq(_accountingExtension.bondedAmountOf(proposer, usdc, _requestId), 0);
  }

  function test_releaseValidResponse_ETH(uint256 _rewardSize, uint256 _bondSize) public {
    // Exception to avoid overflow when depositing.
    vm.assume(_rewardSize < type(uint256).max - _bondSize);

    // Update the parameters of the request.
    _setupRequest(_bondSize, _rewardSize, weth);

    // Requester bonds and creates request.
    _deposit(_accountingExtension, requester, weth, _rewardSize);
    bytes32 _requestId = _createRequest();

    // Proposer bonds and creates request.
    _deposit(_accountingExtension, proposer, weth, _bondSize);
    _proposeResponse();

    // Check: requester has placed the bond?
    assertEq(_accountingExtension.bondedAmountOf(requester, weth, _requestId), _rewardSize);

    // Check: proposer has placed the bond?
    assertEq(_accountingExtension.bondedAmountOf(proposer, weth, _requestId), _bondSize);

    // Warp to finalization time.
    vm.warp(block.timestamp + _expectedDeadline + _baseDisputeWindow);
    // Finalize request/response.
    oracle.finalize(mockRequest, mockResponse);

    // Check: requester has paid for response?
    assertEq(_accountingExtension.balanceOf(requester, weth), 0);

    // Check: requester has no bonded balance left?
    assertEq(_accountingExtension.bondedAmountOf(requester, weth, _requestId), 0);

    // Check: proposer got the reward?
    assertEq(_accountingExtension.balanceOf(proposer, weth), _rewardSize + _bondSize);

    // Check: proposer has no bonded balance left?
    assertEq(_accountingExtension.bondedAmountOf(proposer, weth, _requestId), 0);
  }

  function test_releaseSuccessfulDispute_ERC20(uint256 _rewardSize, uint256 _bondSize) public {
    // Exceptions to avoid overflow when depositing.
    vm.assume(_bondSize < type(uint256).max / 2);
    vm.assume(_rewardSize < type(uint256).max - _bondSize * 2);

    // Update the parameters of the request.
    _setupRequest(_bondSize, _rewardSize, usdc);

    // Requester bonds and creates request.
    _deposit(_accountingExtension, requester, usdc, _rewardSize);
    bytes32 _requestId = _createRequest();

    // Proposer bonds and proposes response.
    _deposit(_accountingExtension, proposer, usdc, _bondSize);
    _proposeResponse();

    // Disputer bonds and disputes response.
    _deposit(_accountingExtension, disputer, usdc, _bondSize);
    bytes32 _disputeId = _disputeResponse();

    // Overriding dispute status and finalizing.
    _finishDispute(_disputeId, IOracle.DisputeStatus.Won);

    // Check: proposer got slashed?
    assertEq(_accountingExtension.balanceOf(proposer, usdc), 0);

    // Check: proposer has no bonded balance left?
    assertEq(_accountingExtension.bondedAmountOf(proposer, usdc, _requestId), 0);

    // Check: disputer got proposer's bond?
    assertEq(_accountingExtension.balanceOf(disputer, usdc), _bondSize * 2);

    // Check: disputer has no bonded balance left?
    assertEq(_accountingExtension.bondedAmountOf(disputer, usdc, _requestId), 0);
  }

  function test_releaseSuccessfulDispute_ETH(uint256 _rewardSize, uint256 _bondSize) public {
    // Exceptions to avoid overflow when depositing.
    vm.assume(_bondSize < type(uint256).max / 2);
    vm.assume(_rewardSize < type(uint256).max - _bondSize * 2);

    // Update the parameters of the request.
    _setupRequest(_bondSize, _rewardSize, weth);

    // Requester bonds and creates request.
    _deposit(_accountingExtension, requester, weth, _rewardSize);
    bytes32 _requestId = _createRequest();

    // Proposer bonds and proposes response.
    _deposit(_accountingExtension, proposer, weth, _bondSize);
    _proposeResponse();

    // Disputer bonds and disputes response.
    _deposit(_accountingExtension, disputer, weth, _bondSize);
    bytes32 _disputeId = _disputeResponse();

    // Overriding dispute status and finalizing.
    _finishDispute(_disputeId, IOracle.DisputeStatus.Won);

    // Check: proposer got slashed?
    assertEq(_accountingExtension.balanceOf(proposer, weth), 0);

    // Check: proposer has no bonded balance left?
    assertEq(_accountingExtension.bondedAmountOf(proposer, weth, _requestId), 0);

    // Check: disputer got proposer's bond?
    assertEq(_accountingExtension.balanceOf(disputer, weth), _bondSize * 2);

    // Check: disputer has no bonded balance left?
    assertEq(_accountingExtension.bondedAmountOf(disputer, weth, _requestId), 0);
  }

  /**
   * @notice Updates the parameters of the mock request.
   */
  function _setupRequest(uint256 _bondSize, uint256 _rewardSize, IERC20 _token) internal {
    mockRequest.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _expectedUrl,
        method: _expectedMethod,
        body: _expectedBody,
        accountingExtension: _accountingExtension,
        paymentToken: _token,
        paymentAmount: _rewardSize
      })
    );

    mockRequest.responseModuleData = abi.encode(
      IBondedResponseModule.RequestParameters({
        accountingExtension: _accountingExtension,
        bondToken: _token,
        bondSize: _bondSize,
        deadline: _expectedDeadline,
        disputeWindow: _baseDisputeWindow
      })
    );

    mockRequest.disputeModuleData = abi.encode(
      IBondedDisputeModule.RequestParameters({
        accountingExtension: _accountingExtension,
        bondToken: _token,
        bondSize: _bondSize
      })
    );

    _resetMockIds();
  }

  /**
   * @notice Simulates a dispute being resolved.
   */
  function _finishDispute(bytes32 _disputeId, IOracle.DisputeStatus _disputeStatus) internal {
    vm.mockCall(address(oracle), abi.encodeCall(IOracle.disputeStatus, _disputeId), abi.encode(_disputeStatus));

    vm.prank(address(oracle));
    _bondedDisputeModule.onDisputeStatusChange(_disputeId, mockRequest, mockResponse, mockDispute);
  }
}
