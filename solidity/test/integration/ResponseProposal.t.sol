// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_ResponseProposal is IntegrationBase {
  bytes32 internal _requestId;
  IOracle.Request internal _request;

  function setUp() public override {
    super.setUp();

    _expectedDeadline = block.timestamp + BLOCK_TIME * 600;

    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedReward, _expectedReward);

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

    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    _requestId = oracle.createRequest(_request, _ipfsHash);
  }

  function test_proposeResponse_validResponse(bytes memory _responseBytes) public {
    _forBondDepositERC20(_accountingExtension, proposer, usdc, _expectedBondSize, _expectedBondSize);

    IOracle.Response memory _response =
      IOracle.Response({proposer: proposer, requestId: _requestId, response: _responseBytes});

    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    oracle.proposeResponse(_request, _response);
    vm.stopPrank();
  }

  function test_proposeResponse_afterDeadline(uint256 _timestamp, bytes memory _responseBytes) public {
    vm.assume(_timestamp > _expectedDeadline);
    _forBondDepositERC20(_accountingExtension, proposer, usdc, _expectedBondSize, _expectedBondSize);

    // Warp to timestamp after deadline
    vm.warp(_timestamp);
    // Check: does revert if deadline is passed?
    vm.expectRevert(IBondedResponseModule.BondedResponseModule_TooLateToPropose.selector);

    IOracle.Response memory _response =
      IOracle.Response({proposer: proposer, requestId: _requestId, response: _responseBytes});

    vm.prank(proposer);
    oracle.proposeResponse(_request, _response);
  }

  function test_proposeResponse_alreadyResponded(bytes memory _responseBytes) public {
    _forBondDepositERC20(_accountingExtension, proposer, usdc, _expectedBondSize, _expectedBondSize);

    IOracle.Response memory _response =
      IOracle.Response({proposer: proposer, requestId: _requestId, response: _responseBytes});

    // First response
    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    oracle.proposeResponse(_request, _response);
    vm.stopPrank();

    // Check: does revert if already responded?
    vm.expectRevert(IBondedResponseModule.BondedResponseModule_AlreadyResponded.selector);

    // Second response
    vm.prank(proposer);
    oracle.proposeResponse(_request, _response);
  }

  function test_proposeResponse_nonExistentRequest(bytes memory _responseBytes, bytes32 _nonExistentRequestId) public {
    vm.assume(_nonExistentRequestId != _requestId);
    _forBondDepositERC20(_accountingExtension, proposer, usdc, _expectedBondSize, _expectedBondSize);

    IOracle.Response memory _response =
      IOracle.Response({proposer: proposer, requestId: _nonExistentRequestId, response: _responseBytes});

    // Check: does revert if request does not exist?
    vm.expectRevert(IOracle.Oracle_InvalidResponseBody.selector);

    vm.prank(proposer);
    oracle.proposeResponse(_request, _response);
  }
  // Proposing without enough funds bonded (should revert insufficient funds)

  function test_proposeResponse_insufficientFunds(bytes memory _responseBytes) public {
    IOracle.Response memory _response =
      IOracle.Response({proposer: proposer, requestId: _requestId, response: _responseBytes});

    // Check: does revert if proposer does not have enough funds bonded?
    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));

    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);
    oracle.proposeResponse(_request, _response);
  }
}
