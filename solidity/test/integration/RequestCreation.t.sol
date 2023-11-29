// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_RequestCreation is IntegrationBase {
  bytes32 internal _requestId;

  function setUp() public override {
    super.setUp();
    _expectedDeadline = block.timestamp + BLOCK_TIME * 600;
  }

  function test_createRequestWithoutResolutionAndFinalityModules() public {
    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedReward, _expectedReward);

    // Request without resolution and finality modules.
    IOracle.Request memory _request = _standardRequest();
    _request.resolutionModule = address(0);
    _request.finalityModule = address(0);
    _request.resolutionModuleData = bytes('');
    _request.finalityModuleData = bytes('');

    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));

    _requestId = oracle.createRequest(_request, _ipfsHash);

    // Check: request data was stored in request module?
    IHttpRequestModule.RequestParameters memory _reqParams =
      _requestModule.decodeRequestData(_request.requestModuleData);

    assertEq(_reqParams.url, _expectedUrl);
    assertEq(uint256(_reqParams.method), uint256(_expectedMethod));
    assertEq(_reqParams.body, _expectedBody);
    assertEq(address(_reqParams.accountingExtension), address(_accountingExtension));
    assertEq(address(_reqParams.paymentToken), address(usdc));
    assertEq(_reqParams.paymentAmount, _expectedReward);

    // Check: request data was stored in response module?
    IBondedResponseModule.RequestParameters memory _params =
      _responseModule.decodeRequestData(_request.responseModuleData);
    assertEq(address(_accountingExtension), address(_params.accountingExtension));
    assertEq(address(_params.bondToken), address(usdc));
    assertEq(_expectedBondSize, _params.bondSize);
    assertEq(_expectedDeadline, _params.deadline);

    // Check: request data was stored in dispute module?
    IBondedDisputeModule.RequestParameters memory _params2 =
      _bondedDisputeModule.decodeRequestData(_request.disputeModuleData);

    assertEq(address(_accountingExtension), address(_params2.accountingExtension));
    assertEq(address(_params.bondToken), address(_params2.bondToken));
    assertEq(_expectedBondSize, _params2.bondSize);
  }

  function test_createRequestWithAllModules() public {
    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedReward, _expectedReward);

    // Request with all modules.
    IOracle.Request memory _request = _standardRequest();

    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    _requestId = oracle.createRequest(_request, _ipfsHash);

    // Check: request data was stored in request module?
    IHttpRequestModule.RequestParameters memory _reqParams =
      _requestModule.decodeRequestData(_request.requestModuleData);

    assertEq(_reqParams.url, _expectedUrl);
    assertEq(uint256(_reqParams.method), uint256(_expectedMethod));
    assertEq(_reqParams.body, _expectedBody);
    assertEq(address(_reqParams.accountingExtension), address(_accountingExtension));
    assertEq(address(_reqParams.paymentToken), address(usdc));
    assertEq(_reqParams.paymentAmount, _expectedReward);

    // Check: request data was stored in response module?
    IBondedResponseModule.RequestParameters memory _params =
      _responseModule.decodeRequestData(_request.responseModuleData);

    assertEq(address(_accountingExtension), address(_params.accountingExtension));
    assertEq(address(_params.bondToken), address(usdc));
    assertEq(_expectedBondSize, _params.bondSize);
    assertEq(_expectedDeadline, _params.deadline);

    // Check: request data was stored in dispute module?
    IBondedDisputeModule.RequestParameters memory _params2 =
      _bondedDisputeModule.decodeRequestData(_request.disputeModuleData);

    assertEq(address(_accountingExtension), address(_params2.accountingExtension));
    assertEq(address(_params.bondToken), address(_params2.bondToken));
    assertEq(_expectedBondSize, _params2.bondSize);

    // Check: request data was stored in resolution module?
    IArbitratorModule.RequestParameters memory _params3 =
      _arbitratorModule.decodeRequestData(_request.resolutionModuleData);
    assertEq(_params3.arbitrator, address(_mockArbitrator));

    // Check: request data was stored in finality module?
    ICallbackModule.RequestParameters memory _callbackParams =
      _callbackModule.decodeRequestData(_request.finalityModuleData);
    assertEq(_callbackParams.target, address(_mockCallback));
    assertEq(_callbackParams.data, abi.encode(_expectedCallbackValue));
  }

  function test_createRequestWithReward_UserHasBonded() public {
    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedReward, _expectedReward);

    // Request with rewards.
    IOracle.Request memory _request = _standardRequest();

    // Check: should not revert as user has bonded.
    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));

    oracle.createRequest(_request, _ipfsHash);
  }

  function test_createRequestWithReward_UserHasNotBonded() public {
    // Request with rewards.
    IOracle.Request memory _request = _standardRequest();

    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));

    // Check: should revert with `InsufficientFunds` as user has not deposited.
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);
    _requestId = oracle.createRequest(_request, _ipfsHash);
  }

  function test_createRequestWithoutReward_UserHasBonded() public {
    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedReward, _expectedReward);

    // Request without rewards.
    IOracle.Request memory _request = _standardRequest();
    _request.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _expectedUrl,
        method: _expectedMethod,
        body: _expectedBody,
        accountingExtension: _accountingExtension,
        paymentToken: IERC20(USDC_ADDRESS),
        paymentAmount: 0
      })
    );
    // Check: should not revert as user has set no rewards and bonded.
    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));

    oracle.createRequest(_request, _ipfsHash);
  }

  function test_createRequestWithoutReward_UserHasNotBonded() public {
    // Request without rewards
    IOracle.Request memory _request = _standardRequest();
    _request.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _expectedUrl,
        method: _expectedMethod,
        body: _expectedBody,
        accountingExtension: _accountingExtension,
        paymentToken: IERC20(USDC_ADDRESS),
        paymentAmount: 0
      })
    );

    vm.startPrank(requester);
    // Approving the request module to bond the requester tokens
    _accountingExtension.approveModule(address(_requestModule));

    // Check: should not revert as user has set no rewards.
    oracle.createRequest(_request, _ipfsHash);
  }

  function test_createRequestDuplicate() public {
    // Double token amount as each request is a unique bond.
    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedReward * 2, _expectedReward * 2);

    IOracle.Request memory _firstRequest = _standardRequest();
    IOracle.Request memory _secondRequest = _standardRequest();

    _secondRequest.nonce = 1;

    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));

    bytes32 _firstRequestId = oracle.createRequest(_firstRequest, _ipfsHash);
    bytes32 _secondRequestId = oracle.createRequest(_secondRequest, _ipfsHash);
    vm.stopPrank();

    assertTrue(_firstRequestId != _secondRequestId, 'Request IDs should not be equal');
  }

  function test_createRequestWithInvalidParameters() public {
    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedReward, _expectedReward);

    // Request with invalid token address.
    IOracle.Request memory _invalidTokenRequest = _standardRequest();
    _invalidTokenRequest.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _expectedUrl,
        method: _expectedMethod,
        body: _expectedBody,
        accountingExtension: _accountingExtension,
        paymentToken: IERC20(address(0)),
        paymentAmount: _expectedReward
      })
    );

    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));

    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);
    oracle.createRequest(_invalidTokenRequest, _ipfsHash);
  }

  function test_createRequestWithDisallowedModule() public {
    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedReward, _expectedReward);

    IOracle.Request memory _request = _standardRequest();
    _request.requestModule = address(_responseModule);
    _request.responseModule = address(_requestModule);

    vm.startPrank(requester);
    // Check: reverts with `EVM error`?
    vm.expectRevert();
    oracle.createRequest(_request, _ipfsHash);

    // Check: switch modules back and give a non-existent module. Reverts?
    vm.expectRevert();
    _request.requestModule = address(_requestModule);
    _request.responseModule = address(_responseModule);
    _request.disputeModule = makeAddr('NON-EXISTENT DISPUTE MODULE');
    oracle.createRequest(_request, _ipfsHash);

    vm.stopPrank();
  }

  function _standardRequest() internal view returns (IOracle.Request memory _request) {
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
  }
}
