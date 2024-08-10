// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IModule} from '@defi-wonderland/prophet-core/solidity/interfaces/IModule.sol';
import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {HttpRequestModule, IHttpRequestModule} from '../../../../contracts/modules/request/HttpRequestModule.sol';

import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';

/**
 * @title HTTP Request Module Unit tests
 */
contract BaseTest is Test, Helpers {
  // Mock request data
  // Fuzzing enums doesn't work: https://github.com/foundry-rs/foundry/issues/871
  IHttpRequestModule.HttpMethod public constant METHOD = IHttpRequestModule.HttpMethod.GET;

  // The target contract
  HttpRequestModule public httpRequestModule;
  // A mock oracle
  IOracle public oracle;
  // A mock accounting extension
  IAccountingExtension public accounting;

  /**
   * @notice Deploy the target and mock oracle+accounting extension
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    accounting = IAccountingExtension(makeAddr('AccountingExtension'));
    vm.etch(address(accounting), hex'069420');

    httpRequestModule = new HttpRequestModule(oracle);
  }
}

contract HttpRequestModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleNameReturnsName() public view {
    assertEq(httpRequestModule.moduleName(), 'HttpRequestModule');
  }

  /**
   * @notice Test that the decodeRequestData function returns the correct values
   */
  function test_decodeRequestData(string memory _url, string memory _body, uint256 _amount, IERC20 _token) public view {
    bytes memory _requestData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _url,
        body: _body,
        method: METHOD,
        accountingExtension: accounting,
        paymentToken: _token,
        paymentAmount: _amount
      })
    );

    // Decode the given request data
    IHttpRequestModule.RequestParameters memory _params = httpRequestModule.decodeRequestData(_requestData);

    // Check: decoded values match original values?
    assertEq(_params.url, _url);
    assertEq(uint256(_params.method), uint256(METHOD));
    assertEq(_params.body, _body);
    assertEq(address(_params.accountingExtension), address(accounting));
    assertEq(address(_params.paymentToken), address(_token));
    assertEq(_params.paymentAmount, _amount);
  }

  /**
   * @notice Test that the validateParameters function correctly checks the parameters
   */
  function test_validateParameters(
    string memory _url,
    string memory _body,
    uint256 _method,
    address _accountingExtension,
    address _paymentToken,
    uint256 _paymentAmount
  ) public view {
    _method = bound(_method, 0, 1);

    IHttpRequestModule.RequestParameters memory _params = IHttpRequestModule.RequestParameters({
      url: _url,
      body: _body,
      method: IHttpRequestModule.HttpMethod(_method),
      accountingExtension: IAccountingExtension(_accountingExtension),
      paymentToken: IERC20(_paymentToken),
      paymentAmount: _paymentAmount
    });

    if (
      address(_params.accountingExtension) == address(0) || address(_params.paymentToken) == address(0)
        || _params.paymentAmount == 0 || bytes(_params.url).length == 0 || bytes(_params.body).length == 0
    ) {
      assertFalse(httpRequestModule.validateParameters(abi.encode(_params)));
    } else {
      assertTrue(httpRequestModule.validateParameters(abi.encode(_params)));
    }
  }
}

contract HttpRequestModule_Unit_FinalizeRequest is BaseTest {
  /**
   * @notice Test that finalizeRequest calls:
   *          - oracle get request
   *          - oracle get response
   *          - accounting extension pay
   *          - accounting extension release
   */
  function test_finalizeWithResponse(
    string calldata _url,
    string calldata _body,
    uint256 _amount,
    IERC20 _token
  ) public {
    _amount = bound(_amount, 0, type(uint248).max);

    // Use the correct accounting parameters
    mockRequest.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _url,
        method: METHOD,
        body: _body,
        accountingExtension: accounting,
        paymentToken: _token,
        paymentAmount: _amount
      })
    );

    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;

    // Mock and expect oracle to return the response's creation time
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.responseCreatedAt, (_getId(mockResponse))), abi.encode(block.timestamp)
    );

    // Mock and expect IAccountingExtension.pay to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(
        IAccountingExtension.pay, (_requestId, mockRequest.requester, mockResponse.proposer, _token, _amount)
      ),
      abi.encode()
    );

    vm.startPrank(address(oracle));
    httpRequestModule.finalizeRequest(mockRequest, mockResponse, address(this));
  }

  function test_finalizeWithoutResponse(
    string calldata _url,
    string calldata _body,
    uint256 _amount,
    IERC20 _token
  ) public {
    _amount = bound(_amount, 0, type(uint248).max);

    // Use the correct accounting parameters
    mockRequest.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _url,
        method: METHOD,
        body: _body,
        accountingExtension: accounting,
        paymentToken: _token,
        paymentAmount: _amount
      })
    );

    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;

    // Mock and expect oracle to return no timestamp
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.responseCreatedAt, (_getId(mockResponse))), abi.encode(0));

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (mockRequest.requester, _requestId, _token, _amount)),
      abi.encode(true)
    );

    vm.startPrank(address(oracle));
    httpRequestModule.finalizeRequest(mockRequest, mockResponse, address(this));
  }

  function test_emitsEvent(string calldata _url, string calldata _body, uint256 _amount, IERC20 _token) public {
    // Use the correct accounting parameters
    mockRequest.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _url,
        method: METHOD,
        body: _body,
        accountingExtension: accounting,
        paymentToken: _token,
        paymentAmount: _amount
      })
    );

    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;

    // Update mock call to return the response's createdAt
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.responseCreatedAt, (_getId(mockResponse))), abi.encode(0));

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (mockRequest.requester, _requestId, _token, _amount)),
      abi.encode(true)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(httpRequestModule));
    emit RequestFinalized(_requestId, mockResponse, address(this));

    vm.prank(address(oracle));
    httpRequestModule.finalizeRequest(mockRequest, mockResponse, address(this));
  }

  /**
   * @notice Test that the finalizeRequest reverts if caller is not the oracle
   */
  function test_revertsIfWrongCaller(address _caller) public {
    vm.assume(_caller != address(oracle));

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);

    vm.prank(_caller);
    httpRequestModule.finalizeRequest(mockRequest, mockResponse, address(_caller));
  }
}
