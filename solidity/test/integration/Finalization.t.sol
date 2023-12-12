// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_Finalization is IntegrationBase {
  bytes internal _responseData;

  address internal _finalizer = makeAddr('finalizer');
  IOracle.Request internal _request;
  IOracle.Response internal _response;
  bytes32 _requestId;
  bytes32 _responseId;

  function setUp() public override {
    super.setUp();
    _expectedDeadline = block.timestamp + BLOCK_TIME * 600;
  }

  /**
   * @notice Test to check if another module can be set as callback module.
   */
  function test_targetIsAnotherModule() public {
    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedBondSize, _expectedBondSize);

    _customFinalizationRequest(
      address(_callbackModule),
      abi.encode(
        ICallbackModule.RequestParameters({
          target: address(_callbackModule),
          data: abi.encodeWithSignature('callback()')
        })
      )
    );

    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    _requestId = oracle.createRequest(_request, _ipfsHash);
    vm.stopPrank();

    _setupFinalizationStage(_request);

    vm.roll(block.number + _baseDisputeWindow);
    vm.prank(_finalizer);
    oracle.finalize(_request, _response);
  }

  /**
   * @notice Test to check that finalization data is set and callback calls are made.
   */
  function test_makeAndIgnoreLowLevelCalls(bytes memory _calldata) public {
    address _callbackTarget = makeAddr('target');
    vm.etch(_callbackTarget, hex'069420');

    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedBondSize, _expectedBondSize);

    _customFinalizationRequest(
      address(_callbackModule),
      abi.encode(ICallbackModule.RequestParameters({target: _callbackTarget, data: _calldata}))
    );

    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    oracle.createRequest(_request, _ipfsHash);
    vm.stopPrank();

    _setupFinalizationStage(_request);

    // Check: all low-level calls are made?
    vm.expectCall(_callbackTarget, _calldata);

    vm.roll(block.number + _baseDisputeWindow);
    vm.prank(_finalizer);
    oracle.finalize(_request, _response);

    bytes32 _finalizedResponse = oracle.getFinalizedResponseId(_requestId);
    // Check: is response finalized?
    assertEq(_finalizedResponse, _responseId);
  }

  /**
   * @notice Test to check that finalizing a request that has no response will revert.
   */
  function test_revertFinalizeIfNoResponse() public {
    address _callbackTarget = makeAddr('target');
    vm.etch(_callbackTarget, hex'069420');

    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedBondSize, _expectedBondSize);

    _customFinalizationRequest(
      address(_callbackModule),
      abi.encode(ICallbackModule.RequestParameters({target: _callbackTarget, data: bytes('')}))
    );

    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    oracle.createRequest(_request, _ipfsHash);
    vm.stopPrank();

    IOracle.Response memory _nonExistentResponse =
      IOracle.Response({proposer: proposer, requestId: _requestId, response: abi.encode('repsonse')});

    vm.prank(_finalizer);

    // Check: reverts if request has no response?
    vm.expectRevert(IOracle.Oracle_InvalidFinalizedResponse.selector);

    oracle.finalize(_request, _nonExistentResponse);
  }

  /**
   * @notice Test to check that finalizing a request with a ongoing dispute with revert.
   */
  function test_revertFinalizeWithDisputedResponse() public {
    address _callbackTarget = makeAddr('target');
    vm.etch(_callbackTarget, hex'069420');

    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedBondSize, _expectedBondSize);

    _customFinalizationRequest(
      address(_callbackModule),
      abi.encode(ICallbackModule.RequestParameters({target: _callbackTarget, data: bytes('')}))
    );

    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    oracle.createRequest(_request, _ipfsHash);
    vm.stopPrank();

    _response = IOracle.Response({proposer: proposer, requestId: _requestId, response: abi.encode('response')});

    _forBondDepositERC20(_accountingExtension, proposer, usdc, _expectedBondSize, _expectedBondSize);
    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    _responseId = oracle.proposeResponse(_request, _response);
    vm.stopPrank();

    _forBondDepositERC20(_accountingExtension, disputer, usdc, _expectedBondSize, _expectedBondSize);
    IOracle.Dispute memory _dispute =
      IOracle.Dispute({proposer: proposer, disputer: disputer, requestId: _requestId, responseId: _responseId});

    vm.startPrank(disputer);
    _accountingExtension.approveModule(address(_bondedDisputeModule));
    oracle.disputeResponse(_request, _response, _dispute);
    vm.stopPrank();

    vm.prank(_finalizer);
    vm.expectRevert(IOracle.Oracle_InvalidFinalizedResponse.selector);
    oracle.finalize(_request, _response);
  }

  /**
   * @notice Test to check that finalizing a request with a ongoing dispute with revert.
   */
  function test_revertFinalizeInDisputeWindow(uint256 _block) public {
    _block = bound(_block, block.number, _expectedDeadline - _baseDisputeWindow - 1);
    address _callbackTarget = makeAddr('target');
    vm.etch(_callbackTarget, hex'069420');

    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedBondSize, _expectedBondSize);

    _customFinalizationRequest(
      address(_callbackModule),
      abi.encode(ICallbackModule.RequestParameters({target: _callbackTarget, data: bytes('')}))
    );

    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    oracle.createRequest(_request, _ipfsHash);
    vm.stopPrank();

    _response = IOracle.Response({proposer: proposer, requestId: _requestId, response: abi.encode('response')});

    _forBondDepositERC20(_accountingExtension, proposer, usdc, _expectedBondSize, _expectedBondSize);
    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    oracle.proposeResponse(_request, _response);
    vm.stopPrank();

    vm.roll(_block);
    vm.prank(_finalizer);
    vm.expectRevert(IBondedResponseModule.BondedResponseModule_TooEarlyToFinalize.selector);
    oracle.finalize(_request, _response);
  }
  /**
   * @notice Test to check that finalizing a request without disputes triggers callback calls and executes without reverting.
   */

  function test_finalizeWithUndisputedResponse(bytes calldata _calldata) public {
    address _callbackTarget = makeAddr('target');
    vm.etch(_callbackTarget, hex'069420');

    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedBondSize, _expectedBondSize);

    _customFinalizationRequest(
      address(_callbackModule),
      abi.encode(ICallbackModule.RequestParameters({target: _callbackTarget, data: _calldata}))
    );

    vm.expectCall(_callbackTarget, _calldata);
    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    oracle.createRequest(_request, _ipfsHash);
    vm.stopPrank();

    _setupFinalizationStage(_request);

    vm.roll(block.number + _baseDisputeWindow);
    vm.prank(_finalizer);
    oracle.finalize(_request, _response);
  }

  /**
   * @notice Test to check that finalizing a request before the disputing deadline will revert.
   */
  function test_revertFinalizeBeforeDeadline(bytes calldata _calldata) public {
    address _callbackTarget = makeAddr('target');
    vm.etch(_callbackTarget, hex'069420');

    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedBondSize, _expectedBondSize);

    _customFinalizationRequest(
      address(_callbackModule),
      abi.encode(ICallbackModule.RequestParameters({target: _callbackTarget, data: _calldata}))
    );

    vm.expectCall(_callbackTarget, _calldata);

    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    oracle.createRequest(_request, _ipfsHash);
    vm.stopPrank();

    _response = IOracle.Response({proposer: proposer, requestId: _requestId, response: abi.encode('response')});

    _forBondDepositERC20(_accountingExtension, proposer, usdc, _expectedBondSize, _expectedBondSize);
    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    oracle.proposeResponse(_request, _response);
    vm.stopPrank();

    vm.prank(_finalizer);
    vm.expectRevert(IBondedResponseModule.BondedResponseModule_TooEarlyToFinalize.selector);
    oracle.finalize(_request, _response);
  }

  /**
   * @notice Internal helper function to setup the finalization stage of a request.
   */
  function _setupFinalizationStage(IOracle.Request memory _requestToFinalize) internal {
    _forBondDepositERC20(_accountingExtension, proposer, usdc, _expectedBondSize, _expectedBondSize);
    _response = IOracle.Response({proposer: proposer, requestId: _requestId, response: abi.encode('response')});

    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    _responseId = oracle.proposeResponse(_requestToFinalize, _response);
    vm.stopPrank();

    vm.roll(_expectedDeadline + 1);
  }

  function _customFinalizationRequest(address _finalityModule, bytes memory _finalityModuleData) internal {
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
      finalityModuleData: _finalityModuleData,
      requestModule: address(_requestModule),
      responseModule: address(_responseModule),
      disputeModule: address(_bondedDisputeModule),
      resolutionModule: address(_arbitratorModule),
      finalityModule: address(_finalityModule)
    });
    _requestId = _getId(_request);
  }
}
