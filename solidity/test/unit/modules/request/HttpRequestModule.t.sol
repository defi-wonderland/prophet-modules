// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IModule} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IModule.sol';

import {HttpRequestModule, IHttpRequestModule} from '../../../../contracts/modules/request/HttpRequestModule.sol';

import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';

/**
 * @dev Harness to set an entry in the requestData mapping, without triggering setup request hooks
 */

contract ForTest_HttpRequestModule is HttpRequestModule {
  constructor(IOracle _oracle) HttpRequestModule(_oracle) {}

  function forTest_setRequestData(bytes32 _requestId, bytes memory _data) public {
    requestData[_requestId] = _data;
  }
}

/**
 * @title HTTP Request Module Unit tests
 */
contract BaseTest is Test, Helpers {
  // Mock request data
  string public constant URL = 'https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd';
  IHttpRequestModule.HttpMethod public constant METHOD = IHttpRequestModule.HttpMethod.GET;
  string public constant BODY = '69420';

  // Mock token
  IERC20 public immutable TOKEN = IERC20(makeAddr('ERC20'));
  // The target contract
  ForTest_HttpRequestModule public httpRequestModule;
  // A mock oracle
  IOracle public oracle;
  // A mock accounting extension
  IAccountingExtension public accounting = IAccountingExtension(makeAddr('accounting'));

  event RequestFinalized(bytes32 indexed _requestId, address _finalizer);

  /**
   * @notice Deploy the target and mock oracle+accounting extension
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    accounting = IAccountingExtension(makeAddr('AccountingExtension'));
    vm.etch(address(accounting), hex'069420');

    httpRequestModule = new ForTest_HttpRequestModule(oracle);
  }
}

contract HttpRequestModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleNameReturnsName() public {
    assertEq(httpRequestModule.moduleName(), 'HttpRequestModule');
  }

  /**
   * @notice Test that the decodeRequestData function returns the correct values
   */
  function test_decodeRequestData(bytes32 _requestId, uint256 _amount, IERC20 _token) public {
    bytes memory _requestData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: URL,
        method: METHOD,
        body: BODY,
        accountingExtension: accounting,
        paymentToken: _token,
        paymentAmount: _amount
      })
    );

    // Set the request data
    httpRequestModule.forTest_setRequestData(_requestId, _requestData);

    // Decode the given request data
    IHttpRequestModule.RequestParameters memory _params = httpRequestModule.decodeRequestData(_requestId);

    // Check: decoded values match original values?
    assertEq(_params.url, URL);
    assertEq(uint256(_params.method), uint256(METHOD));
    assertEq(_params.body, BODY);
    assertEq(address(_params.accountingExtension), address(accounting));
    assertEq(address(_params.paymentToken), address(_token));
    assertEq(_params.paymentAmount, _amount);
  }
}

contract HttpRequestModule_Unit_Setup is BaseTest {
  /**
   * @notice Test that the afterSetupRequest hook:
   *          - decodes the request data
   *          - gets the request from the oracle
   *          - calls the bond function on the accounting extension
   */
  function test_afterSetupRequestTriggered(
    bytes32 _requestId,
    address _requester,
    uint256 _amount,
    IERC20 _token
  ) public {
    bytes memory _requestData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: URL,
        method: METHOD,
        body: BODY,
        accountingExtension: accounting,
        paymentToken: _token,
        paymentAmount: _amount
      })
    );

    IOracle.Request memory _fullRequest;
    _fullRequest.requester = _requester;

    // Mock and expect IOracle.getRequest to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getRequest, (_requestId)), abi.encode(_fullRequest));

    // Mock and expect IAccountingExtension.bond to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeWithSignature('bond(address,bytes32,address,uint256)', _requester, _requestId, _token, _amount),
      abi.encode(true)
    );

    vm.prank(address(oracle));
    httpRequestModule.setupRequest(_requestId, _requestData);
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
  function test_makesCalls(
    bytes32 _requestId,
    address _requester,
    address _proposer,
    uint256 _amount,
    IERC20 _token
  ) public {
    _amount = bound(_amount, 0, type(uint248).max);

    // Use the correct accounting parameters
    bytes memory _requestData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: URL,
        method: METHOD,
        body: BODY,
        accountingExtension: accounting,
        paymentToken: _token,
        paymentAmount: _amount
      })
    );

    IOracle.Request memory _fullRequest;
    _fullRequest.requester = _requester;

    IOracle.Response memory _fullResponse;
    _fullResponse.proposer = _proposer;
    _fullResponse.createdAt = block.timestamp;

    // Set the request data
    httpRequestModule.forTest_setRequestData(_requestId, _requestData);

    // Mock and expect IOracle.getRequest to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getRequest, (_requestId)), abi.encode(_fullRequest));

    // Mock and expect IOracle.getFinalizedResponse to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.getFinalizedResponse, (_requestId)), abi.encode(_fullResponse)
    );

    // Mock and expect IAccountingExtension.pay to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, _requester, _proposer, _token, _amount)),
      abi.encode()
    );

    vm.startPrank(address(oracle));
    httpRequestModule.finalizeRequest(_requestId, address(oracle));

    // Test the release flow
    _fullResponse.createdAt = 0;

    // Update mock call to return the response with createdAt = 0
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.getFinalizedResponse, (_requestId)), abi.encode(_fullResponse)
    );

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_requester, _requestId, _token, _amount)),
      abi.encode(true)
    );

    httpRequestModule.finalizeRequest(_requestId, address(this));
  }

  function test_emitsEvent(
    bytes32 _requestId,
    address _requester,
    address _proposer,
    uint256 _amount,
    IERC20 _token
  ) public {
    // Use the correct accounting parameters
    bytes memory _requestData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: URL,
        method: METHOD,
        body: BODY,
        accountingExtension: accounting,
        paymentToken: _token,
        paymentAmount: _amount
      })
    );

    IOracle.Request memory _fullRequest;
    _fullRequest.requester = _requester;

    IOracle.Response memory _fullResponse;
    _fullResponse.proposer = _proposer;
    _fullResponse.createdAt = block.timestamp;

    // Set the request data
    httpRequestModule.forTest_setRequestData(_requestId, _requestData);

    // Mock and expect IOracle.getRequest to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getRequest, (_requestId)), abi.encode(_fullRequest));

    // Mock and expect IOracle.getFinalizedResponse to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.getFinalizedResponse, (_requestId)), abi.encode(_fullResponse)
    );

    // Mock and expect IAccountingExtension.pay to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IAccountingExtension.pay, (_requestId, _requester, _proposer, _token, _amount)),
      abi.encode()
    );

    vm.startPrank(address(oracle));
    httpRequestModule.finalizeRequest(_requestId, address(oracle));

    // Test the release flow
    _fullResponse.createdAt = 0;

    // Update mock call to return the response with createdAt = 0
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.getFinalizedResponse, (_requestId)), abi.encode(_fullResponse)
    );

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_requester, _requestId, _token, _amount)),
      abi.encode(true)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(httpRequestModule));
    emit RequestFinalized(_requestId, address(this));

    httpRequestModule.finalizeRequest(_requestId, address(this));
  }

  /**
   * @notice Test that the finalizeRequest reverts if caller is not the oracle
   */
  function test_revertsIfWrongCaller(bytes32 _requestId, address _caller) public {
    vm.assume(_caller != address(oracle));

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(abi.encodeWithSelector(IModule.Module_OnlyOracle.selector));

    vm.prank(_caller);
    httpRequestModule.finalizeRequest(_requestId, address(_caller));
  }
}
