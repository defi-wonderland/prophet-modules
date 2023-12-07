// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_Payments is IntegrationBase {
  bytes32 internal _requestId;
  bytes32 internal _responseId;

  function setUp() public override {
    super.setUp();
    _expectedDeadline = block.timestamp + BLOCK_TIME * 600;
  }

  function test_releaseValidResponse_ERC20(uint256 _rewardSize, uint256 _bondSize) public {
    // Exception to avoid overflow when depositing.
    vm.assume(_rewardSize < type(uint256).max - _bondSize);

    // Requester bonds and creates a request.
    _forBondDepositERC20(_accountingExtension, requester, usdc, _rewardSize, _rewardSize);
    IOracle.Request memory _erc20Request = _standardRequest(_rewardSize, _bondSize, usdc);
    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    _requestId = oracle.createRequest(_erc20Request, _ipfsHash);
    vm.stopPrank();

    IOracle.Response memory _response =
      IOracle.Response({proposer: proposer, requestId: _requestId, response: abi.encode('response')});

    // Proposer bonds and proposes a response.
    _forBondDepositERC20(_accountingExtension, proposer, usdc, _bondSize, _bondSize);
    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    _responseId = oracle.proposeResponse(_erc20Request, _response);
    vm.stopPrank();

    // Check that both users have had their funds bonded.
    uint256 _requesterBondedBalanceBefore = _accountingExtension.bondedAmountOf(requester, usdc, _requestId);
    assertEq(_requesterBondedBalanceBefore, _rewardSize);

    uint256 _proposerBondedBalanceBefore = _accountingExtension.bondedAmountOf(proposer, usdc, _requestId);
    assertEq(_proposerBondedBalanceBefore, _bondSize);

    // Warp to finalization time.
    vm.roll(_expectedDeadline + _baseDisputeWindow);
    // Finalize request/response
    oracle.finalize(_erc20Request, _response);

    uint256 _requesterBalanceAfter = _accountingExtension.balanceOf(requester, usdc);
    uint256 _proposerBalanceAfter = _accountingExtension.balanceOf(proposer, usdc);

    // Check: requester paid for response?
    assertEq(_requesterBalanceAfter, 0);
    // Check: proposer got the reward + the bonded amount back?
    assertEq(_proposerBalanceAfter, _rewardSize + _bondSize);

    uint256 _requesterBondedBalanceAfter = _accountingExtension.bondedAmountOf(requester, usdc, _requestId);

    uint256 _proposerBondedBalanceAfter = _accountingExtension.bondedAmountOf(proposer, usdc, _requestId);

    assertEq(_requesterBondedBalanceAfter, 0);
    assertEq(_proposerBondedBalanceAfter, 0);
  }

  function test_releaseValidResponse_ETH(uint256 _rewardSize, uint256 _bondSize) public {
    // Exception to avoid overflow when depositing.
    vm.assume(_rewardSize < type(uint256).max - _bondSize);

    // Requester bonds and creates request.
    _forBondDepositERC20(_accountingExtension, requester, IERC20(address(weth)), _rewardSize, _rewardSize);
    IOracle.Request memory _ethRequest = _standardRequest(_rewardSize, _bondSize, weth);
    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    _requestId = oracle.createRequest(_ethRequest, _ipfsHash);
    vm.stopPrank();

    IOracle.Response memory _response =
      IOracle.Response({proposer: proposer, requestId: _requestId, response: abi.encode('response')});

    // Proposer bonds and creates request.
    _forBondDepositERC20(_accountingExtension, proposer, IERC20(address(weth)), _bondSize, _bondSize);
    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    _responseId = oracle.proposeResponse(_ethRequest, _response);
    vm.stopPrank();

    // Check that both users have had their funds bonded.
    uint256 _requesterBondedBalanceBefore = _accountingExtension.bondedAmountOf(requester, weth, _requestId);
    assertEq(_requesterBondedBalanceBefore, _rewardSize);

    uint256 _proposerBondedBalanceBefore = _accountingExtension.bondedAmountOf(proposer, weth, _requestId);
    assertEq(_proposerBondedBalanceBefore, _bondSize);

    // Warp to finalization time.
    vm.roll(_expectedDeadline + _baseDisputeWindow);
    // Finalize request/response.
    oracle.finalize(_ethRequest, _response);

    uint256 _requesterBalanceAfter = _accountingExtension.balanceOf(requester, weth);
    uint256 _proposerBalanceAfter = _accountingExtension.balanceOf(proposer, weth);

    // Check: requester has no balance left?
    assertEq(_requesterBalanceAfter, 0);
    // Check: proposer got the reward + the bonded amount back?
    assertEq(_proposerBalanceAfter, _rewardSize + _bondSize);

    uint256 _requesterBondedBalanceAfter = _accountingExtension.bondedAmountOf(requester, weth, _requestId);

    uint256 _proposerBondedBalanceAfter = _accountingExtension.bondedAmountOf(proposer, weth, _requestId);

    assertEq(_requesterBondedBalanceAfter, 0);
    assertEq(_proposerBondedBalanceAfter, 0);
  }

  function test_releaseSuccessfulDispute_ERC20(uint256 _rewardSize, uint256 _bondSize) public {
    // Exceptions to avoid overflow when depositing.
    vm.assume(_bondSize < type(uint256).max / 2);
    vm.assume(_rewardSize < type(uint256).max - _bondSize * 2);

    // Requester bonds and creates request.
    _forBondDepositERC20(_accountingExtension, requester, usdc, _rewardSize, _rewardSize);
    IOracle.Request memory _erc20Request = _standardRequest(_rewardSize, _bondSize, usdc);
    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    _requestId = oracle.createRequest(_erc20Request, _ipfsHash);
    vm.stopPrank();

    IOracle.Response memory _response =
      IOracle.Response({proposer: proposer, requestId: _requestId, response: abi.encode('response')});

    // Proposer bonds and proposes response.
    _forBondDepositERC20(_accountingExtension, proposer, usdc, _bondSize, _bondSize);
    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    _responseId = oracle.proposeResponse(_erc20Request, _response);
    vm.stopPrank();

    IOracle.Dispute memory _dispute =
      IOracle.Dispute({disputer: disputer, proposer: proposer, responseId: _responseId, requestId: _requestId});
    // Disputer bonds and disputes response.
    _forBondDepositERC20(_accountingExtension, disputer, usdc, _bondSize, _bondSize);
    vm.startPrank(disputer);
    _accountingExtension.approveModule(address(_bondedDisputeModule));
    bytes32 _disputeId = oracle.disputeResponse(_erc20Request, _response, _dispute);
    vm.stopPrank();

    // Overriding dispute status and finalizing.
    vm.mockCall(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, _disputeId), abi.encode(IOracle.DisputeStatus.Won)
    );
    vm.prank(address(oracle));
    _bondedDisputeModule.onDisputeStatusChange(_disputeId, _erc20Request, _response, _dispute);

    uint256 _proposerBalanceAfter = _accountingExtension.balanceOf(proposer, usdc);
    uint256 _disputerBalanceAfter = _accountingExtension.balanceOf(disputer, usdc);

    // Check: proposer get slashed?
    assertEq(_proposerBalanceAfter, 0);
    // Check: disputer gets proposer's bond?
    assertEq(_disputerBalanceAfter, _bondSize * 2);

    uint256 _proposerBondedBalanceAfter = _accountingExtension.bondedAmountOf(proposer, usdc, _requestId);

    uint256 _disputerBondedBalanceAfter = _accountingExtension.bondedAmountOf(disputer, usdc, _requestId);

    assertEq(_proposerBondedBalanceAfter, 0);
    assertEq(_disputerBondedBalanceAfter, 0);
  }

  function test_releaseSuccessfulDispute_ETH(uint256 _rewardSize, uint256 _bondSize) public {
    // Exceptions to avoid overflow when depositing.
    vm.assume(_bondSize < type(uint256).max / 2);
    vm.assume(_rewardSize < type(uint256).max - _bondSize * 2);

    // Requester bonds and creates request.
    _forBondDepositERC20(_accountingExtension, requester, weth, _rewardSize, _rewardSize);
    IOracle.Request memory _erc20Request = _standardRequest(_rewardSize, _bondSize, weth);
    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    _requestId = oracle.createRequest(_erc20Request, _ipfsHash);
    vm.stopPrank();

    IOracle.Response memory _response =
      IOracle.Response({proposer: proposer, requestId: _requestId, response: abi.encode('response')});

    // Proposer bonds and proposes response.
    _forBondDepositERC20(_accountingExtension, proposer, weth, _bondSize, _bondSize);
    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    _responseId = oracle.proposeResponse(_erc20Request, _response);
    vm.stopPrank();

    IOracle.Dispute memory _dispute =
      IOracle.Dispute({disputer: disputer, proposer: proposer, responseId: _responseId, requestId: _requestId});

    // Disputer bonds and disputes response.
    _forBondDepositERC20(_accountingExtension, disputer, weth, _bondSize, _bondSize);
    vm.startPrank(disputer);
    _accountingExtension.approveModule(address(_bondedDisputeModule));
    bytes32 _disputeId = oracle.disputeResponse(_erc20Request, _response, _dispute);
    vm.stopPrank();

    // Overriding dispute status and finalizing.
    vm.mockCall(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, _disputeId), abi.encode(IOracle.DisputeStatus.Won)
    );
    vm.prank(address(oracle));
    _bondedDisputeModule.onDisputeStatusChange(_disputeId, _erc20Request, _response, _dispute);

    uint256 _proposerBalanceAfter = _accountingExtension.balanceOf(proposer, weth);
    uint256 _disputerBalanceAfter = _accountingExtension.balanceOf(disputer, weth);

    // Check: proposer get slashed?
    assertEq(_proposerBalanceAfter, 0);
    // Check: disputer gets proposer's bond?
    assertEq(_disputerBalanceAfter, _bondSize * 2);

    uint256 _proposerBondedBalanceAfter = _accountingExtension.bondedAmountOf(proposer, weth, _requestId);

    uint256 _disputerBondedBalanceAfter = _accountingExtension.bondedAmountOf(disputer, weth, _requestId);

    assertEq(_proposerBondedBalanceAfter, 0);
    assertEq(_disputerBondedBalanceAfter, 0);
  }

  function _standardRequest(
    uint256 _rewardSize,
    uint256 _bondSize,
    IERC20 _paymentToken
  ) internal view returns (IOracle.Request memory _request) {
    _request = IOracle.Request({
      nonce: 0,
      requester: requester,
      requestModuleData: abi.encode(
        IHttpRequestModule.RequestParameters({
          url: _expectedUrl,
          method: _expectedMethod,
          body: _expectedBody,
          accountingExtension: _accountingExtension,
          paymentToken: _paymentToken,
          paymentAmount: _rewardSize
        })
        ),
      responseModuleData: abi.encode(
        IBondedResponseModule.RequestParameters({
          accountingExtension: _accountingExtension,
          bondToken: _paymentToken,
          bondSize: _bondSize,
          deadline: _expectedDeadline,
          disputeWindow: _baseDisputeWindow
        })
        ),
      disputeModuleData: abi.encode(
        IBondedDisputeModule.RequestParameters({
          accountingExtension: _accountingExtension,
          bondToken: _paymentToken,
          bondSize: _bondSize
        })
        ),
      resolutionModuleData: abi.encode(_mockArbitrator),
      finalityModuleData: abi.encode(
        ICallbackModule.RequestParameters({target: address(_mockCallback), data: abi.encode(_expectedCallbackValue)})
        ),
      requestModule: address(_requestModule),
      responseModule: address(_responseModule),
      disputeModule: address(_bondedDisputeModule),
      resolutionModule: address(_arbitratorModule),
      finalityModule: address(_callbackModule)
    });
  }
}
