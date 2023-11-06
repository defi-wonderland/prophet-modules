// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IModule} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IModule.sol';

import {
  CircuitResolverModule,
  ICircuitResolverModule
} from '../../../../contracts/modules/dispute/CircuitResolverModule.sol';

import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';

/**
 * @dev Harness to set an entry in the requestData mapping, without triggering setup request hooks
 */
contract ForTest_CircuitResolverModule is CircuitResolverModule {
  constructor(IOracle _oracle) CircuitResolverModule(_oracle) {}

  function forTest_setCorrectResponse(bytes32 _requestId, bytes memory _data) public {
    _correctResponses[_requestId] = _data;
  }
}

/**
 * @title Bonded Dispute Module Unit tests
 */
contract BaseTest is Test, Helpers {
  // The target contract
  ForTest_CircuitResolverModule public circuitResolverModule;
  // A mock oracle
  IOracle public oracle;
  // A mock accounting extension
  IAccountingExtension public accountingExtension;

  // A mock circuit verifier address
  address public circuitVerifier;
  // 100% random sequence of bytes representing request, response, or dispute id
  bytes32 public mockId = bytes32('69');

  // Create a new dummy response
  IOracle.Response public mockResponse;
  // Create a new dummy dispute
  IOracle.Dispute public mockDispute;

  // Mock addresses
  IERC20 public _token = IERC20(makeAddr('token'));
  address public _disputer = makeAddr('disputer');
  address public _proposer = makeAddr('proposer');
  bytes internal _callData = abi.encodeWithSignature('test(uint256)', 123);

  event DisputeStatusChanged(bytes32 _disputeId, IOracle.Dispute _dispute, IOracle.DisputeStatus _status);
  event ResponseDisputed(
    bytes32 indexed _responseId, bytes32 indexed _disputeId, IOracle.Dispute _dispute, uint256 _blockNumber
  );

  /**
   * @notice Deploy the target and mock oracle+accounting extension
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    accountingExtension = IAccountingExtension(makeAddr('AccountingExtension'));
    vm.etch(address(accountingExtension), hex'069420');
    circuitVerifier = makeAddr('CircuitVerifier');
    vm.etch(address(circuitVerifier), hex'069420');

    circuitResolverModule = new ForTest_CircuitResolverModule(oracle);

    mockDispute = IOracle.Dispute({disputer: _disputer, responseId: mockId, proposer: _proposer, requestId: mockId});

    mockResponse = IOracle.Response({proposer: _proposer, requestId: mockId, response: bytes('')});
  }
}

contract CircuitResolverModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the decodeRequestData function returns the correct values
   */
  function test_decodeRequestData_returnsCorrectData(
    address _accountingExtension,
    address _randomToken,
    uint256 _bondSize
  ) public {
    // Mock data
    bytes memory _requestData = abi.encode(
      ICircuitResolverModule.RequestParameters({
        callData: _callData,
        verifier: circuitVerifier,
        accountingExtension: IAccountingExtension(_accountingExtension),
        bondToken: IERC20(_randomToken),
        bondSize: _bondSize
      })
    );

    // Test: decode the given request data
    ICircuitResolverModule.RequestParameters memory _params = circuitResolverModule.decodeRequestData(_requestData);

    // Check: is the request data properly stored?
    assertEq(_params.callData, _callData, 'Mismatch: decoded calldata');
    assertEq(_params.verifier, circuitVerifier, 'Mismatch: decoded circuit verifier');
    assertEq(address(_params.accountingExtension), _accountingExtension, 'Mismatch: decoded accounting extension');
    assertEq(address(_params.bondToken), _randomToken, 'Mismatch: decoded token');
    assertEq(_params.bondSize, _bondSize, 'Mismatch: decoded bond size');
  }

  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleNameReturnsName() public {
    assertEq(circuitResolverModule.moduleName(), 'CircuitResolverModule');
  }
}

contract CircuitResolverModule_Unit_DisputeResponse is BaseTest {
  /**
   * @notice Test if dispute incorrect response returns the correct status
   */
  function test_disputeIncorrectResponse(IOracle.Request calldata _request) public {
    bytes32 _requestId = _getId(_request);
    bool _correctResponse = false;

    // Create new Response memory struct with random values
    IOracle.Response memory _response =
      IOracle.Response({proposer: _proposer, requestId: _requestId, response: abi.encode(true)});

    mockDispute.requestId = _requestId;
    mockDispute.responseId = _getId(_request);

    // Mock and expect the call to the verifier
    _mockAndExpect(circuitVerifier, _callData, abi.encode(_correctResponse));

    // Test: call disputeResponse
    vm.prank(address(oracle));
    circuitResolverModule.disputeResponse(_request, _response, mockDispute);
  }

  function test_emitsEvent(IOracle.Request calldata _request, uint256 _bondSize) public {
    bytes32 _requestId = _getId(_request);
    bool _correctResponse = false;

    mockResponse.requestId = _requestId;
    mockResponse.response = abi.encode(true);

    // Mock and expect the call to the verifier
    _mockAndExpect(circuitVerifier, _callData, abi.encode(_correctResponse));

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(circuitResolverModule));
    emit ResponseDisputed({
      _responseId: mockDispute.responseId,
      _disputeId: _getId(mockDispute),
      _dispute: mockDispute,
      _blockNumber: block.number
    });

    vm.prank(address(oracle));
    circuitResolverModule.disputeResponse(_request, mockResponse, mockDispute);
  }

  /**
   * @notice Test if dispute correct response returns the correct status
   */
  function test_disputeCorrectResponse(
    IOracle.Request calldata _request,
    bytes32 _responseId,
    uint256 _bondSize
  ) public {
    bytes32 _requestId = _getId(_request);
    bytes memory _encodedCorrectResponse = abi.encode(true);

    // Create new Response memory struct with random values
    mockResponse.requestId = _requestId;
    mockResponse.response = _encodedCorrectResponse;

    // Mock and expect the call to the verifier
    _mockAndExpect(circuitVerifier, _callData, _encodedCorrectResponse);

    vm.prank(address(oracle));
    circuitResolverModule.disputeResponse(_request, mockResponse, mockDispute);
  }

  /**
   * @notice Test if dispute response reverts when called by caller who's not the oracle
   */
  function test_revertWrongCaller(address _randomCaller, IOracle.Request calldata _request) public {
    vm.assume(_randomCaller != address(oracle));

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(abi.encodeWithSelector(IModule.Module_OnlyOracle.selector));

    vm.prank(_randomCaller);
    circuitResolverModule.disputeResponse(_request, mockResponse, mockDispute);
  }
}

contract CircuitResolverModule_Unit_OnDisputeStatusChange is BaseTest {
  function test_eventEmitted(IOracle.Request calldata _request, bytes32 _responseId, uint256 _bondSize) public {
    bytes32 _requestId = _getId(_request);
    bytes memory _encodedCorrectResponse = abi.encode(true);

    circuitResolverModule.forTest_setCorrectResponse(_requestId, _encodedCorrectResponse);

    mockResponse.requestId = _requestId;
    mockResponse.response = _encodedCorrectResponse;
    mockResponse.proposer = mockDispute.disputer;

    // Mock and expect the call to the oracle, finalizing the request
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.finalize, (_request, mockResponse)), abi.encode(true));

    // Populate the mock dispute with the correct values
    mockDispute.responseId = _responseId;
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);
    IOracle.DisputeStatus _status = IOracle.DisputeStatus.Lost;

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(circuitResolverModule));
    emit DisputeStatusChanged(_disputeId, mockDispute, _status);

    vm.prank(address(oracle));
    circuitResolverModule.onDisputeStatusChange(_disputeId, _request, mockResponse, mockDispute);
  }
}
