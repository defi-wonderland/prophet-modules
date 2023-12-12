// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IModule} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IModule.sol';

import {
  ContractCallRequestModule,
  IContractCallRequestModule
} from '../../../../contracts/modules/request/ContractCallRequestModule.sol';

import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';

/**
 * @title Contract Call Request Module Unit tests
 */
contract BaseTest is Test, Helpers {
  // The target contract
  ContractCallRequestModule public contractCallRequestModule;
  // A mock oracle
  IOracle public oracle;
  // A mock accounting extension
  IAccountingExtension public accounting;
  // A mock user for testing
  address internal _user = makeAddr('user');
  // A second mock user for testing
  address internal _user2 = makeAddr('user2');
  // A mock ERC20 token
  IERC20 internal _token = IERC20(makeAddr('ERC20'));
  // Mock data
  address internal _targetContract = address(_token);
  bytes4 internal _functionSelector = bytes4(abi.encodeWithSignature('allowance(address,address)'));
  bytes internal _dataParams = abi.encode(_user, _user2);

  /**
   * @notice Deploy the target and mock oracle+accounting extension
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    accounting = IAccountingExtension(makeAddr('AccountingExtension'));
    vm.etch(address(accounting), hex'069420');

    contractCallRequestModule = new ContractCallRequestModule(oracle);
  }
}

contract ContractCallRequestModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleNameReturnsName() public {
    assertEq(contractCallRequestModule.moduleName(), 'ContractCallRequestModule', 'Wrong module name');
  }

  /**
   * @notice Test that the decodeRequestData function returns the correct values
   */
  function test_decodeRequestData(IERC20 _paymentToken, uint256 _paymentAmount) public {
    bytes memory _requestData = abi.encode(
      IContractCallRequestModule.RequestParameters({
        target: _targetContract,
        functionSelector: _functionSelector,
        data: _dataParams,
        accountingExtension: accounting,
        paymentToken: _paymentToken,
        paymentAmount: _paymentAmount
      })
    );

    // Decode the given request data
    IContractCallRequestModule.RequestParameters memory _params =
      contractCallRequestModule.decodeRequestData(_requestData);

    // Check: decoded values match original values?
    assertEq(_params.target, _targetContract, 'Mismatch: decoded target');
    assertEq(_params.functionSelector, _functionSelector, 'Mismatch: decoded function selector');
    assertEq(_params.data, _dataParams, 'Mismatch: decoded data');
    assertEq(address(_params.accountingExtension), address(accounting), 'Mismatch: decoded accounting extension');
    assertEq(address(_params.paymentToken), address(_paymentToken), 'Mismatch: decoded payment token');
    assertEq(_params.paymentAmount, _paymentAmount, 'Mismatch: decoded payment amount');
  }
}

contract ContractCallRequestModule_Unit_CreateRequest is BaseTest {
  function test_createRequest(
    address _requester,
    IContractCallRequestModule.RequestParameters memory _params
  ) public assumeFuzzable(_requester) assumeFuzzable(address(_params.accountingExtension)) {
    mockRequest.requestModuleData = abi.encode(_params);
    mockRequest.requester = _requester;

    // Mock and expect the bond to be placed
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeWithSignature(
        'bond(address,bytes32,address,uint256)',
        _requester,
        _getId(mockRequest),
        _params.paymentToken,
        _params.paymentAmount
      ),
      abi.encode()
    );

    vm.prank(address(oracle));
    contractCallRequestModule.createRequest(_getId(mockRequest), mockRequest.requestModuleData, _requester);
  }
}

contract ContractCallRequestModule_Unit_FinalizeRequest is BaseTest {
  /**
   * @notice Test that finalizeRequest calls:
   *          - oracle get request
   *          - oracle get response
   *          - accounting extension pay
   *          - accounting extension release
   */
  function test_finalizeWithResponse(IERC20 _paymentToken, uint256 _paymentAmount) public {
    mockRequest.requestModuleData = abi.encode(
      IContractCallRequestModule.RequestParameters({
        target: _targetContract,
        functionSelector: _functionSelector,
        data: _dataParams,
        accountingExtension: accounting,
        paymentToken: _paymentToken,
        paymentAmount: _paymentAmount
      })
    );

    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;

    // Mock and expect oracle to return the response's creation time
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.createdAt, (_getId(mockResponse))), abi.encode(block.timestamp)
    );

    // Mock and expect IAccountingExtension.pay to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(
        IAccountingExtension.pay,
        (_requestId, mockRequest.requester, mockResponse.proposer, _paymentToken, _paymentAmount)
      ),
      abi.encode()
    );

    vm.startPrank(address(oracle));
    contractCallRequestModule.finalizeRequest(mockRequest, mockResponse, address(oracle));
  }

  function test_finalizeWithoutResponse(IERC20 _paymentToken, uint256 _paymentAmount) public {
    mockRequest.requestModuleData = abi.encode(
      IContractCallRequestModule.RequestParameters({
        target: _targetContract,
        functionSelector: _functionSelector,
        data: _dataParams,
        accountingExtension: accounting,
        paymentToken: _paymentToken,
        paymentAmount: _paymentAmount
      })
    );

    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;

    // Mock and expect oracle to return no timestamp
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.createdAt, (_getId(mockResponse))), abi.encode(0));

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (mockRequest.requester, _requestId, _paymentToken, _paymentAmount)),
      abi.encode(true)
    );

    vm.startPrank(address(oracle));
    contractCallRequestModule.finalizeRequest(mockRequest, mockResponse, address(oracle));
  }

  function test_emitsEvent(IERC20 _paymentToken, uint256 _paymentAmount) public {
    // Use the correct accounting parameters
    mockRequest.requestModuleData = abi.encode(
      IContractCallRequestModule.RequestParameters({
        target: _targetContract,
        functionSelector: _functionSelector,
        data: _dataParams,
        accountingExtension: accounting,
        paymentToken: _paymentToken,
        paymentAmount: _paymentAmount
      })
    );

    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;

    // Mock and expect oracle to return no timestamp
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.createdAt, (_getId(mockResponse))), abi.encode(0));

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (mockRequest.requester, _requestId, _paymentToken, _paymentAmount)),
      abi.encode(true)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(contractCallRequestModule));
    emit RequestFinalized(_requestId, mockResponse, address(this));

    vm.prank(address(oracle));
    contractCallRequestModule.finalizeRequest(mockRequest, mockResponse, address(this));
  }

  /**
   * @notice Test that the finalizeRequest reverts if caller is not the oracle
   */
  function test_revertsIfWrongCaller(address _caller, IOracle.Request calldata _request) public {
    vm.assume(_caller != address(oracle));

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);

    vm.prank(_caller);
    contractCallRequestModule.finalizeRequest(_request, mockResponse, address(_caller));
  }
}
