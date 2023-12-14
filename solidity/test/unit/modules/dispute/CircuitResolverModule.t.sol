// SPDX-License-Identifier: MIT
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
import {MockVerifier} from '../../../mocks/MockVerifier.sol';

/**
 * @dev Harness to set an entry in the correctResponses mapping
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
  // A mock circuit verifier address
  MockVerifier public mockVerifier;

  // Events
  event DisputeStatusChanged(bytes32 indexed _disputeId, IOracle.Dispute _dispute, IOracle.DisputeStatus _status);
  event ResponseDisputed(
    bytes32 indexed _requestId,
    bytes32 indexed _responseId,
    bytes32 indexed _disputeId,
    IOracle.Dispute _dispute,
    uint256 _blockNumber
  );

  /**
   * @notice Deploy the target and mock oracle+accounting extension
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    mockVerifier = new MockVerifier();

    circuitResolverModule = new ForTest_CircuitResolverModule(oracle);
  }
}

contract CircuitResolverModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the decodeRequestData function returns the correct values
   */
  function test_decodeRequestData(
    IAccountingExtension _accountingExtension,
    IERC20 _randomToken,
    uint256 _bondSize,
    bytes memory _callData
  ) public {
    // Mock data
    bytes memory _requestData = abi.encode(
      ICircuitResolverModule.RequestParameters({
        callData: _callData,
        verifier: address(mockVerifier),
        accountingExtension: IAccountingExtension(_accountingExtension),
        bondToken: IERC20(_randomToken),
        bondSize: _bondSize
      })
    );

    // Test: decode the given request data
    ICircuitResolverModule.RequestParameters memory _params = circuitResolverModule.decodeRequestData(_requestData);

    // Check: is the request data properly stored?
    assertEq(
      address(_params.accountingExtension), address(_accountingExtension), 'Mismatch: decoded accounting extension'
    );
    assertEq(address(_params.bondToken), address(_randomToken), 'Mismatch: decoded token');
    assertEq(_params.verifier, address(mockVerifier), 'Mismatch: decoded circuit verifier');
    assertEq(_params.bondSize, _bondSize, 'Mismatch: decoded bond size');
    assertEq(_params.callData, _callData, 'Mismatch: decoded calldata');
  }

  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleName() public {
    assertEq(circuitResolverModule.moduleName(), 'CircuitResolverModule');
  }
}

contract CircuitResolverModule_Unit_DisputeResponse is BaseTest {
  /**
   * @notice Test if dispute incorrect response returns the correct status
   */
  function test_disputeIncorrectResponse(
    IAccountingExtension _accountingExtension,
    IERC20 _randomToken,
    uint256 _bondSize,
    bytes memory _callData
  ) public {
    _callData = abi.encodeWithSelector(mockVerifier.calculateRoot.selector, _callData);

    mockRequest.disputeModuleData = abi.encode(
      ICircuitResolverModule.RequestParameters({
        callData: _callData,
        verifier: address(mockVerifier),
        accountingExtension: _accountingExtension,
        bondToken: _randomToken,
        bondSize: _bondSize
      })
    );

    bool _correctResponse = false;

    mockResponse.requestId = _getId(mockRequest);
    mockDispute.requestId = mockResponse.requestId;
    mockDispute.responseId = _getId(mockResponse);

    // Mock and expect the call to the verifier
    _mockAndExpect(address(mockVerifier), _callData, abi.encode(_correctResponse));

    // Mock and expect the call the oracle, updating the dispute's status
    _mockAndExpect(
      address(oracle),
      abi.encodeWithSelector(
        oracle.updateDisputeStatus.selector, mockRequest, mockResponse, mockDispute, IOracle.DisputeStatus.Won
      ),
      abi.encode(true)
    );

    // Test: call disputeResponse
    vm.prank(address(oracle));
    circuitResolverModule.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  function test_emitsEvent(
    IAccountingExtension _accountingExtension,
    IERC20 _randomToken,
    uint256 _bondSize,
    bytes memory _callData
  ) public {
    mockRequest.disputeModuleData = abi.encode(
      ICircuitResolverModule.RequestParameters({
        callData: _callData,
        verifier: address(mockVerifier),
        accountingExtension: _accountingExtension,
        bondToken: _randomToken,
        bondSize: _bondSize
      })
    );

    bytes32 _requestId = _getId(mockRequest);
    bool _correctResponse = false;

    mockResponse.requestId = _requestId;
    mockResponse.response = abi.encode(true);

    // Mock and expect the call to the verifier
    _mockAndExpect(address(mockVerifier), _callData, abi.encode(_correctResponse));

    // Mock and expect the call the oracle, updating the dispute's status
    _mockAndExpect(
      address(oracle),
      abi.encodeWithSelector(
        oracle.updateDisputeStatus.selector, mockRequest, mockResponse, mockDispute, IOracle.DisputeStatus.Won
      ),
      abi.encode(true)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(circuitResolverModule));
    emit ResponseDisputed({
      _requestId: mockResponse.requestId,
      _responseId: mockDispute.responseId,
      _disputeId: _getId(mockDispute),
      _dispute: mockDispute,
      _blockNumber: block.number
    });

    vm.prank(address(oracle));
    circuitResolverModule.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Test if dispute correct response returns the correct status
   */
  function test_disputeCorrectResponse(
    IAccountingExtension _accountingExtension,
    IERC20 _randomToken,
    uint256 _bondSize,
    bytes memory _callData
  ) public {
    _callData = abi.encodeWithSelector(mockVerifier.calculateRoot.selector, _callData);

    mockRequest.disputeModuleData = abi.encode(
      ICircuitResolverModule.RequestParameters({
        callData: _callData,
        verifier: address(mockVerifier),
        accountingExtension: _accountingExtension,
        bondToken: _randomToken,
        bondSize: _bondSize
      })
    );

    bytes memory _encodedCorrectResponse = abi.encode(true);

    mockResponse.requestId = _getId(mockRequest);
    mockResponse.response = _encodedCorrectResponse;

    // Mock and expect the call to the verifier
    _mockAndExpect(address(mockVerifier), _callData, _encodedCorrectResponse);

    // Mock and expect the call the oracle, updating the dispute's status
    _mockAndExpect(
      address(oracle),
      abi.encodeWithSelector(
        oracle.updateDisputeStatus.selector, mockRequest, mockResponse, mockDispute, IOracle.DisputeStatus.Lost
      ),
      abi.encode(true)
    );

    vm.prank(address(oracle));
    circuitResolverModule.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Test if dispute response reverts when called by caller who's not the oracle
   */
  function test_revertWrongCaller(address _randomCaller) public {
    vm.assume(_randomCaller != address(oracle));

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);

    vm.prank(_randomCaller);
    circuitResolverModule.disputeResponse(mockRequest, mockResponse, mockDispute);
  }
}

contract CircuitResolverModule_Unit_OnDisputeStatusChange is BaseTest {
  function test_emitsEvent_lostDispute(
    IAccountingExtension _accountingExtension,
    IERC20 _randomToken,
    uint256 _bondSize,
    bytes memory _callData
  ) public assumeFuzzable(address(_accountingExtension)) {
    mockRequest.disputeModuleData = abi.encode(
      ICircuitResolverModule.RequestParameters({
        callData: _callData,
        verifier: address(mockVerifier),
        accountingExtension: _accountingExtension,
        bondToken: _randomToken,
        bondSize: _bondSize
      })
    );

    bytes32 _requestId = _getId(mockRequest);
    bytes memory _encodedCorrectResponse = abi.encode(true);

    circuitResolverModule.forTest_setCorrectResponse(_requestId, _encodedCorrectResponse);

    mockResponse.requestId = _requestId;
    mockResponse.response = _encodedCorrectResponse;
    mockResponse.proposer = makeAddr('proposer');

    // Populate the mock dispute with the correct values
    mockDispute.responseId = _getId(mockResponse);
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);
    IOracle.DisputeStatus _status = IOracle.DisputeStatus.Lost;

    // Mock and expect the call to the oracle, getting the dispute status
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(_status));

    // Mock and expect the call to the oracle, finalizing the request
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.finalize, (mockRequest, mockResponse)), abi.encode());

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(circuitResolverModule));
    emit DisputeStatusChanged(_disputeId, mockDispute, _status);

    vm.prank(address(oracle));
    circuitResolverModule.onDisputeStatusChange(_disputeId, mockRequest, mockResponse, mockDispute);
  }

  function test_emitsEvent_wonDispute(
    IAccountingExtension _accountingExtension,
    IERC20 _randomToken,
    uint256 _bondSize,
    bytes memory _callData
  ) public assumeFuzzable(address(_accountingExtension)) {
    mockRequest.disputeModuleData = abi.encode(
      ICircuitResolverModule.RequestParameters({
        callData: _callData,
        verifier: address(mockVerifier),
        accountingExtension: _accountingExtension,
        bondToken: _randomToken,
        bondSize: _bondSize
      })
    );

    bytes32 _requestId = _getId(mockRequest);
    bytes memory _encodedCorrectResponse = abi.encode(true);

    circuitResolverModule.forTest_setCorrectResponse(_requestId, _encodedCorrectResponse);

    mockResponse.requestId = _requestId;
    mockResponse.response = abi.encode(false);
    mockResponse.proposer = makeAddr('proposer');

    // Populate the mock dispute with the correct values
    mockDispute.responseId = _getId(mockResponse);
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);
    IOracle.DisputeStatus _status = IOracle.DisputeStatus.Won;

    // Mock and expect the call to the oracle, getting the dispute status
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(_status));

    // Mock and expect the call to the accounting extension, paying the disputer
    _mockAndExpect(
      address(_accountingExtension),
      abi.encodeCall(
        IAccountingExtension.pay, (_requestId, makeAddr('proposer'), mockDispute.disputer, _randomToken, _bondSize)
      ),
      abi.encode()
    );

    IOracle.Response memory _newResponse =
      IOracle.Response({requestId: _requestId, response: _encodedCorrectResponse, proposer: mockDispute.disputer});

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(circuitResolverModule));
    emit DisputeStatusChanged(_disputeId, mockDispute, _status);

    // Mock and expect the call to the oracle, proposing the correct response
    _mockAndExpect(
      address(oracle),
      abi.encodeCall(IOracle.proposeResponse, (mockRequest, _newResponse)),
      abi.encode(_getId(_newResponse))
    );

    // Mock and expect the call to the accounting extension, paying the disputer
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.finalize, (mockRequest, _newResponse)), abi.encode());

    vm.prank(address(oracle));
    circuitResolverModule.onDisputeStatusChange(_disputeId, mockRequest, mockResponse, mockDispute);
  }
}
