// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_ResponseDispute is IntegrationBase {
  bytes internal _responseData;
  bytes32 internal _requestId;
  bytes32 internal _responseId;

  IOracle.Request internal _request;
  IOracle.Response internal _response;
  IOracle.Dispute internal _dispute;

  function setUp() public override {
    super.setUp();

    _expectedDeadline = block.timestamp + BLOCK_TIME * 600;
    _responseData = abi.encode('response');

    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedBondSize, _expectedBondSize);

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
    vm.stopPrank();

    _forBondDepositERC20(_accountingExtension, proposer, usdc, _expectedBondSize, _expectedBondSize);

    _response = IOracle.Response({proposer: proposer, requestId: _requestId, response: _responseData});

    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    _responseId = oracle.proposeResponse(_request, _response);
    vm.stopPrank();

    _dispute = IOracle.Dispute({disputer: disputer, proposer: proposer, responseId: _responseId, requestId: _requestId});
  }

  // check that the dispute id is stored in the response struct
  function test_disputeResponse_disputeIdStoredInResponse() public {
    _forBondDepositERC20(_accountingExtension, disputer, usdc, _expectedBondSize, _expectedBondSize);

    vm.startPrank(disputer);
    _accountingExtension.approveModule(address(_bondedDisputeModule));
    oracle.disputeResponse(_request, _response, _dispute);
    vm.stopPrank();
  }

  // dispute a non-existent response
  function test_disputeResponse_nonExistentResponse(bytes32 _nonExistentResponseId) public {
    vm.assume(_nonExistentResponseId != _responseId);
    _dispute.responseId = _nonExistentResponseId;

    vm.prank(disputer);

    vm.expectRevert(IOracle.Oracle_InvalidDisputeBody.selector);
    oracle.disputeResponse(_request, _response, _dispute);
  }

  function test_disputeResponse_requestAndResponseMismatch() public {
    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedBondSize, _expectedBondSize);
    IOracle.Request memory _secondRequest = IOracle.Request({
      nonce: 1,
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
        _accountingExtension, USDC_ADDRESS, _expectedBondSize, _expectedDeadline, _baseDisputeWindow
        ),
      disputeModuleData: abi.encode(
        _accountingExtension, USDC_ADDRESS, _expectedBondSize, _expectedDeadline, _mockArbitrator
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
    vm.prank(requester);
    bytes32 _secondRequestId = oracle.createRequest(_secondRequest, _ipfsHash);

    _forBondDepositERC20(_accountingExtension, proposer, usdc, _expectedBondSize, _expectedBondSize);
    _response.requestId = _secondRequestId;
    vm.prank(proposer);
    oracle.proposeResponse(_secondRequest, _response);

    vm.prank(disputer);
    vm.expectRevert(IOracle.Oracle_InvalidDisputeBody.selector);
    oracle.disputeResponse(_request, _response, _dispute);
  }

  function test_disputeResponse_noBondedFunds() public {
    vm.startPrank(disputer);
    _accountingExtension.approveModule(address(_bondedDisputeModule));
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);
    oracle.disputeResponse(_request, _response, _dispute);
  }

  function test_disputeResponse_alreadyFinalized() public {
    vm.roll(_expectedDeadline + _baseDisputeWindow);
    oracle.finalize(_request, _response);

    vm.prank(disputer);
    vm.expectRevert(abi.encodeWithSelector(IOracle.Oracle_AlreadyFinalized.selector, _requestId));
    oracle.disputeResponse(_request, _response, _dispute);
  }

  function test_disputeResponse_alreadyDisputed() public {
    _forBondDepositERC20(_accountingExtension, disputer, usdc, _expectedBondSize, _expectedBondSize);
    vm.startPrank(disputer);
    _accountingExtension.approveModule(address(_bondedDisputeModule));
    oracle.disputeResponse(_request, _response, _dispute);
    vm.stopPrank();

    vm.prank(disputer);
    vm.expectRevert(abi.encodeWithSelector(IOracle.Oracle_ResponseAlreadyDisputed.selector, _responseId));
    oracle.disputeResponse(_request, _response, _dispute);
  }

  // TODO: discuss and decide on the implementation of a dispute deadline
  //   function test_disputeResponse_afterDeadline(uint256 _timestamp) public {
  //     vm.assume(_timestamp > _expectedDeadline);
  //     _bondDisputerFunds();
  //     vm.warp(_timestamp);
  //     vm.prank(disputer);
  //     vm.expectRevert(abi.encodeWithSelector(IBondedDisputeModule.BondedDisputeModule_TooLateToDispute.selector, _responseId));
  //     oracle.disputeResponse(_requestId, _responseId);
  //   }
}
