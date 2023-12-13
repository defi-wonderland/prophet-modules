// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_RequestCreation is IntegrationBase {
  function setUp() public override {
    super.setUp();

    vm.prank(requester);
    _accountingExtension.approveModule(address(_requestModule));

    // Deposit the bond
    _deposit(_accountingExtension, requester, usdc, _expectedReward);
  }

  function test_createRequest_withoutResolutionAndFinalityModules() public {
    // Request without resolution and finality modules.
    mockRequest.resolutionModule = address(0);
    mockRequest.finalityModule = address(0);
    mockRequest.resolutionModuleData = bytes('');
    mockRequest.finalityModuleData = bytes('');

    // Create the request
    vm.prank(requester);
    bytes32 _requestId = oracle.createRequest(mockRequest, _ipfsHash);

    // Check: saved the correct id?
    assertEq(_requestId, _getId(mockRequest));
  }

  function test_createRequest_withAllModules() public {
    // Create the request
    vm.prank(requester);
    bytes32 _requestId = oracle.createRequest(mockRequest, _ipfsHash);

    // Check: saved the correct id?
    assertEq(_requestId, _getId(mockRequest));
  }

  function test_createRequest_withReward_UserHasBonded() public {
    // Check: should not revert as user has bonded.
    vm.prank(requester);
    oracle.createRequest(mockRequest, _ipfsHash);
  }

  function test_createRequest_withReward_UserHasNotBonded() public {
    // Using WETH as the payment token and not depositing into the accounting extension
    mockRequest.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _expectedUrl,
        method: _expectedMethod,
        body: _expectedBody,
        accountingExtension: _accountingExtension,
        paymentToken: weth,
        paymentAmount: _expectedReward
      })
    );

    // Check: should revert with `InsufficientFunds` as user has not deposited?
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);
    vm.prank(requester);
    oracle.createRequest(mockRequest, _ipfsHash);
  }

  function test_createRequest_withoutReward_UserHasBonded() public {
    // Request without rewards
    mockRequest.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _expectedUrl,
        method: _expectedMethod,
        body: _expectedBody,
        accountingExtension: _accountingExtension,
        paymentToken: usdc,
        paymentAmount: 0
      })
    );

    // Check: should not revert as user has set no rewards and bonded?
    vm.prank(requester);
    oracle.createRequest(mockRequest, _ipfsHash);
  }

  function test_createRequest_withoutReward_UserHasNotBonded() public {
    // Request without rewards
    mockRequest.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _expectedUrl,
        method: _expectedMethod,
        body: _expectedBody,
        accountingExtension: _accountingExtension,
        paymentToken: usdc,
        paymentAmount: 0
      })
    );

    // Check: doesn't revert if the reward is 0 and the user has not bonded?
    vm.prank(requester);
    oracle.createRequest(mockRequest, _ipfsHash);
  }

  function test_createRequest_duplicate() public {
    // Double token amount as each request is a unique bond.
    _deposit(_accountingExtension, requester, usdc, _expectedReward * 2);

    // Create the first request
    vm.startPrank(requester);
    bytes32 _firstRequestId = oracle.createRequest(mockRequest, _ipfsHash);

    // Set the new nonce and create the second request
    mockRequest.nonce += 1;
    bytes32 _secondRequestId = oracle.createRequest(mockRequest, _ipfsHash);
    vm.stopPrank();

    // Check: saved different ids?
    assertTrue(_firstRequestId != _secondRequestId, 'Request IDs should not be equal');
  }

  function test_createRequest_withInvalidParameters() public {
    // Request with invalid token address.
    mockRequest.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _expectedUrl,
        method: _expectedMethod,
        body: _expectedBody,
        accountingExtension: _accountingExtension,
        paymentToken: IERC20(address(0)),
        paymentAmount: _expectedReward
      })
    );

    // Check: reverts due to the invalid token address?
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);
    vm.prank(requester);
    oracle.createRequest(mockRequest, _ipfsHash);
  }

  function test_createRequest_withDisallowedModule() public {
    mockRequest.requestModule = address(_responseModule);
    mockRequest.responseModule = address(_requestModule);

    vm.startPrank(requester);

    // Check: reverts with `EVM error`?
    vm.expectRevert();
    oracle.createRequest(mockRequest, _ipfsHash);

    // Reset the modules back and configure an invalid dispute module.
    mockRequest.requestModule = address(_requestModule);
    mockRequest.responseModule = address(_responseModule);
    mockRequest.disputeModule = makeAddr('NON-EXISTENT DISPUTE MODULE');

    // Check: doesn't revert if any module but the request module is invalid?
    oracle.createRequest(mockRequest, _ipfsHash);

    vm.stopPrank();
  }
}
