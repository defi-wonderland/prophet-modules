// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {
  BondedResponseModule,
  IBondedResponseModule,
  IModule,
  IOracle
} from '../../../../contracts/modules/response/BondedResponseModule.sol';

import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';

/**
 * @title Bonded Response Module Unit tests
 */
contract BaseTest is Test, Helpers {
  // The target contract
  BondedResponseModule public bondedResponseModule;
  // A mock oracle
  IOracle public oracle;
  // A mock accounting extension
  IAccountingExtension public accounting = IAccountingExtension(makeAddr('Accounting'));
  // Base dispute window
  uint256 internal _baseDisputeWindow = 12 hours;
  // Mock creation timestamps
  uint256 public requestCreatedAt;
  uint256 public responseCreatedAt;

  // Events
  event ResponseProposed(bytes32 indexed _requestId, IOracle.Response _response);
  event UnutilizedResponseReleased(bytes32 indexed _requestId, bytes32 indexed _responseId);

  /**
   * @notice Deploy the target and mock oracle+accounting extension
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    // Avoid starting at 0 for time sensitive tests
    vm.warp(123_456);
    requestCreatedAt = block.timestamp;
    responseCreatedAt = requestCreatedAt + 30 seconds;

    bondedResponseModule = new BondedResponseModule(oracle);
  }
}

contract BondedResponseModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleNameReturnsName() public view {
    assertEq(bondedResponseModule.moduleName(), 'BondedResponseModule');
  }

  /**
   * @notice Test that the decodeRequestData function returns the correct values
   */
  function test_decodeRequestData(
    IERC20 _token,
    uint256 _bondSize,
    uint256 _deadline,
    uint256 _disputeWindow
  ) public view {
    // Create and set some mock request data
    bytes memory _data = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);

    // Get the returned values
    IBondedResponseModule.RequestParameters memory _params = bondedResponseModule.decodeRequestData(_data);

    // Check: correct values returned?
    assertEq(address(_params.accountingExtension), address(accounting), 'Mismatch: accounting extension address');
    assertEq(address(_params.bondToken), address(_token), 'Mismatch: token address');
    assertEq(_params.bondSize, _bondSize, 'Mismatch: bond size');
    assertEq(_params.deadline, _deadline, 'Mismatch: deadline');
    assertEq(_params.disputeWindow, _disputeWindow, 'Mismatch: dispute window');
  }

  /**
   * @notice Test that the validateParameters function correctly checks the parameters
   */
  function test_validateParameters(IBondedResponseModule.RequestParameters calldata _params) public view {
    if (
      address(_params.accountingExtension) == address(0) || address(_params.bondToken) == address(0)
        || _params.bondSize == 0 || _params.disputeWindow == 0 || _params.deadline == 0
    ) {
      assertFalse(bondedResponseModule.validateParameters(abi.encode(_params)));
    } else {
      assertTrue(bondedResponseModule.validateParameters(abi.encode(_params)));
    }
  }
}

contract BondedResponseModule_Unit_Propose is BaseTest {
  /**
   * @notice Test that the propose function is only callable by the oracle
   */
  function test_revertIfNotOracle(address _sender) public {
    vm.assume(_sender != address(oracle));

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);

    vm.prank(address(_sender));
    bondedResponseModule.propose(mockRequest, mockResponse, _sender);
  }

  /**
   * @notice Test that the propose function works correctly and bonds the proposer's funds
   */
  function test_propose(
    IERC20 _token,
    uint256 _bondSize,
    uint256 _deadline,
    uint256 _disputeWindow,
    address _proposer
  ) public assumeFuzzable(_proposer) {
    _deadline = bound(_deadline, 1, type(uint248).max);
    _disputeWindow = bound(_disputeWindow, 61, 365 days);
    _bondSize = bound(_bondSize, 0, type(uint248).max);

    // Set the response module parameters
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);

    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;
    mockResponse.proposer = _proposer;

    // Mock and expect IOracle.requestCreatedAt to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.requestCreatedAt, (_requestId)), abi.encode(requestCreatedAt)
    );

    // Mock and expect IOracle.getResponseIds to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponseIds, _requestId), abi.encode(new bytes32[](0)));

    // Mock and expect IAccountingExtension.bond to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeWithSignature('bond(address,bytes32,address,uint256)', _proposer, _requestId, _token, _bondSize),
      abi.encode()
    );

    vm.prank(address(oracle));
    bondedResponseModule.propose(mockRequest, mockResponse, _proposer);
  }

  function test_emitsEvent(
    IERC20 _token,
    uint256 _bondSize,
    uint256 _deadline,
    uint256 _disputeWindow,
    address _proposer
  ) public {
    _deadline = bound(_deadline, 1, type(uint248).max);
    _disputeWindow = bound(_disputeWindow, 61, 365 days);

    // Create and set some mock request data
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;
    mockResponse.proposer = _proposer;

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.requestCreatedAt, (_requestId)), abi.encode(requestCreatedAt)
    );

    // Mock and expect IOracle.getResponseIds to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponseIds, _requestId), abi.encode(new bytes32[](0)));

    // Mock and expect IOracle.getResponseIds to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeWithSignature('bond(address,bytes32,address,uint256)', _proposer, _requestId, _token, _bondSize),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondedResponseModule));
    emit ResponseProposed({_requestId: _requestId, _response: mockResponse});

    vm.prank(address(oracle));
    bondedResponseModule.propose(mockRequest, mockResponse, _proposer);
  }

  /**
   * @notice Test that the propose function works correctly and bonds the proposer's funds when the sender is different than the proposer
   */
  function test_propose_another_sender(
    IERC20 _token,
    uint256 _bondSize,
    uint256 _deadline,
    uint256 _disputeWindow,
    address _sender,
    address _proposer
  ) public assumeFuzzable(_sender) assumeFuzzable(_proposer) {
    vm.assume(_sender != _proposer);
    _deadline = bound(_deadline, 1, type(uint248).max);
    _disputeWindow = bound(_disputeWindow, 61, 365 days);
    _bondSize = bound(_bondSize, 0, type(uint248).max);

    // Set the response module parameters
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);

    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;
    mockResponse.proposer = _proposer;

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.requestCreatedAt, (_requestId)), abi.encode(requestCreatedAt)
    );

    // Mock and expect IOracle.getResponseIds to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponseIds, _requestId), abi.encode(new bytes32[](0)));

    // Mock and expect IAccountingExtension.bond to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeWithSignature(
        'bond(address,bytes32,address,uint256,address)', _proposer, _requestId, _token, _bondSize, _sender
      ),
      abi.encode()
    );

    vm.prank(address(oracle));
    bondedResponseModule.propose(mockRequest, mockResponse, _sender);
  }
}

contract BondedResponseModule_Unit_FinalizeRequest is BaseTest {
  /**
   * @notice Test that the propose function is only callable by the oracle
   */
  function test_revertIfNotOracle(address _sender) public {
    vm.assume(_sender != address(oracle));

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);

    vm.prank(address(_sender));
    bondedResponseModule.finalizeRequest(mockRequest, mockResponse, _sender);
  }

  function test_revertsBeforeDeadline(
    uint256 _responseCreationTimestamp,
    uint256 _finalizationTimestamp,
    uint256 _deadline,
    uint256 _disputeWindow
  ) public {
    // Amount of blocks to wait before finalizing a response
    _disputeWindow = bound(_disputeWindow, 10, 90_000);
    // Last timestamp in which a response can be proposed
    _deadline = bound(_deadline, 1, type(uint248).max);
    // Block in which the response was proposed
    _responseCreationTimestamp = bound(
      _responseCreationTimestamp, requestCreatedAt + _deadline - _disputeWindow + 1, requestCreatedAt + _deadline - 1
    );
    // Block in which the request will be tried to be finalized
    _finalizationTimestamp =
      bound(_finalizationTimestamp, requestCreatedAt + _deadline, _responseCreationTimestamp + _disputeWindow - 1);

    // Check revert if deadline has not passed
    mockRequest.responseModuleData = abi.encode(
      IBondedResponseModule.RequestParameters({
        accountingExtension: accounting,
        bondToken: IERC20(makeAddr('token')),
        bondSize: 999_999,
        deadline: _deadline,
        disputeWindow: _disputeWindow
      })
    );
    mockResponse.requestId = _getId(mockRequest);

    // Mock and expect IOracle.allowedModule to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_getId(mockRequest), address(this))), abi.encode(false)
    );

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.requestCreatedAt, (_getId(mockRequest))), abi.encode(requestCreatedAt)
    );

    // Check: does it revert if it's too early to finalize?
    vm.expectRevert(IBondedResponseModule.BondedResponseModule_TooEarlyToFinalize.selector);

    vm.warp(requestCreatedAt + _deadline - 1);
    vm.prank(address(oracle));
    bondedResponseModule.finalizeRequest(mockRequest, mockResponse, address(this));

    // Mock and expect IOracle.allowedModule to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_getId(mockRequest), address(this))), abi.encode(false)
    );

    // Mock and expect IOracle.responseCreatedAt to be called
    _mockAndExpect(
      address(oracle),
      abi.encodeCall(IOracle.responseCreatedAt, (_getId(mockResponse))),
      abi.encode(_responseCreationTimestamp)
    );

    // Check: does it revert if it's too early to finalize?
    vm.expectRevert(IBondedResponseModule.BondedResponseModule_TooEarlyToFinalize.selector);

    vm.warp(_finalizationTimestamp);
    vm.prank(address(oracle));
    bondedResponseModule.finalizeRequest(mockRequest, mockResponse, address(this));
  }

  function test_releasesBond(
    IERC20 _token,
    uint256 _bondSize,
    uint256 _deadline,
    uint256 _disputeWindow,
    address _proposer
  ) public {
    _disputeWindow = bound(_disputeWindow, 61, 365 days);

    // Check correct calls are made if deadline has passed
    _deadline = bound(_deadline, 1, type(uint248).max);
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);
    mockResponse.requestId = _getId(mockRequest);
    mockResponse.proposer = _proposer;

    // Mock and expect IOracle.allowedModule to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_getId(mockRequest), address(this))), abi.encode(true)
    );

    // Mock and expect IOracle.responseCreatedAt to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.responseCreatedAt, (_getId(mockResponse))), abi.encode(responseCreatedAt)
    );

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_proposer, _getId(mockRequest), _token, _bondSize)),
      abi.encode(true)
    );

    vm.warp(responseCreatedAt + _disputeWindow);

    vm.prank(address(oracle));
    bondedResponseModule.finalizeRequest(mockRequest, mockResponse, address(this));
  }

  function test_emitsEvent(
    IERC20 _token,
    uint256 _bondSize,
    uint256 _disputeWindow,
    address _proposer,
    uint256 _deadline
  ) public {
    _disputeWindow = bound(_disputeWindow, 61, 365 days);

    // Check correct calls are made if deadline has passed
    _deadline = bound(_deadline, 1, type(uint248).max);
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;
    mockResponse.proposer = _proposer;

    // Mock and expect IOracle.allowedModule to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, address(this))), abi.encode(false)
    );

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.requestCreatedAt, (_getId(mockRequest))), abi.encode(requestCreatedAt)
    );

    // Mock and expect IOracle.responseCreatedAt to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.responseCreatedAt, (_getId(mockResponse))), abi.encode(block.timestamp)
    );

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_proposer, _getId(mockRequest), _token, _bondSize)),
      abi.encode(true)
    );

    // Check: is event emitted?
    vm.expectEmit(true, true, true, true, address(bondedResponseModule));
    emit RequestFinalized({_requestId: _getId(mockRequest), _response: mockResponse, _finalizer: address(this)});

    vm.warp(requestCreatedAt + _deadline + _disputeWindow);

    vm.prank(address(oracle));
    bondedResponseModule.finalizeRequest(mockRequest, mockResponse, address(this));
  }

  /**
   * @notice Test that the finalize function can be called by an allowed module before the time window.
   */
  function test_earlyByModule(
    IERC20 _token,
    uint256 _bondSize,
    uint256 _deadline,
    address _proposer,
    address _allowedModule
  ) public assumeFuzzable(_allowedModule) {
    _deadline = bound(_deadline, 1, type(uint248).max);
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _baseDisputeWindow);

    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;
    mockResponse.proposer = _proposer;

    // Mock and expect IOracle.allowedModule to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _allowedModule)), abi.encode(true)
    );

    // Mock and expect IOracle.responseCreatedAt to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.responseCreatedAt, (_getId(mockResponse))), abi.encode(responseCreatedAt)
    );

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_proposer, _requestId, _token, _bondSize)),
      abi.encode(true)
    );

    vm.prank(address(oracle));
    bondedResponseModule.finalizeRequest(mockRequest, mockResponse, _allowedModule);
  }

  /**
   * @notice Test that the finalizing a request during a response dispute window will revert.
   */
  function test_revertDuringDisputeWindow(
    IERC20 _token,
    uint256 _bondSize,
    uint256 _deadline,
    address _finalizer
  ) public {
    _deadline = bound(_deadline, block.timestamp + 1, type(uint248).max);

    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _baseDisputeWindow);
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;

    // Mock and expect IOracle.allowedModule to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _finalizer)), abi.encode(false));

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.requestCreatedAt, (_requestId)), abi.encode(requestCreatedAt)
    );

    vm.expectRevert(IBondedResponseModule.BondedResponseModule_TooEarlyToFinalize.selector);

    vm.prank(address(oracle));
    bondedResponseModule.finalizeRequest(mockRequest, mockResponse, _finalizer);
  }

  function test_finalizeWithoutResponse(
    IERC20 _token,
    uint256 _bondSize,
    uint256 _disputeWindow,
    address _proposer,
    uint256 _deadline
  ) public {
    _disputeWindow = bound(_disputeWindow, 61, 365 days);

    // Check correct calls are made if deadline has passed
    _deadline = bound(_deadline, 1, type(uint248).max);
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;
    mockResponse.proposer = _proposer;

    // Mock and expect IOracle.allowedModule to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, address(this))), abi.encode(false)
    );

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.requestCreatedAt, (_getId(mockRequest))), abi.encode(requestCreatedAt)
    );

    // Empty response
    mockResponse = IOracle.Response({proposer: address(0), requestId: bytes32(0), response: bytes('')});

    // Response does not exist
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.responseCreatedAt, (_getId(mockResponse))), abi.encode(0));

    // Check: is event emitted?
    vm.expectEmit(true, true, true, true, address(bondedResponseModule));
    emit RequestFinalized({_requestId: _getId(mockRequest), _response: mockResponse, _finalizer: address(this)});

    vm.warp(requestCreatedAt + _deadline + _disputeWindow);

    vm.prank(address(oracle));
    bondedResponseModule.finalizeRequest(mockRequest, mockResponse, address(this));
  }
}

contract BondedResponseModule_Unit_ReleaseUnutilizedResponse is BaseTest {
  /**
   * @notice Finalized request, undisputed response, the bond should be released
   */
  function test_withUndisputedResponse_withFinalizedRequest_releasesBond(
    IERC20 _token,
    uint256 _bondSize,
    uint256 _deadline,
    bytes32 _finalizedResponseId
  ) public {
    // Setting the response module data
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _baseDisputeWindow);

    // Updating IDs
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;
    mockResponse.proposer = proposer;
    bytes32 _responseId = _getId(mockResponse);

    // Can't claim back the bond of the response that was finalized
    vm.assume(_finalizedResponseId > 0);
    vm.assume(_finalizedResponseId != _responseId);

    // Mock and expect IOracle.disputeOf to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeOf, (_responseId)), abi.encode(bytes32(0)));

    // Mock and expect IOracle.finalizedResponseId to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.finalizedResponseId, (_requestId)), abi.encode(_finalizedResponseId)
    );

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.responseCreatedAt, (_responseId)), abi.encode(block.timestamp)
    );

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (proposer, _getId(mockRequest), _token, _bondSize)),
      abi.encode(true)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondedResponseModule));
    emit UnutilizedResponseReleased(_requestId, _responseId);

    // Test: does it release the bond?
    bondedResponseModule.releaseUnutilizedResponse(mockRequest, mockResponse);
  }

  /**
   * @notice Non-finalized request, undisputed response, the call should revert
   */
  function test_withUndisputedResponse_revertsIfRequestIsNotFinalized(
    IERC20 _token,
    uint256 _bondSize,
    uint256 _deadline,
    address _proposer
  ) public {
    // Setting the response module data
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _baseDisputeWindow);

    // Updating IDs
    bytes32 _requestId = _getId(mockRequest);
    IOracle.Response memory _response = _getResponse(mockRequest, _proposer);
    bytes32 _responseId = _getId(_response);

    // Mock and expect IOracle.disputeOf to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeOf, (_responseId)), abi.encode(bytes32(0)));

    // Mock and expect IOracle.finalizedResponseId to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.finalizedResponseId, (_requestId)), abi.encode(0));

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.responseCreatedAt, (_responseId)), abi.encode(block.timestamp)
    );

    // Check: reverts?
    vm.expectRevert(IBondedResponseModule.BondedResponseModule_InvalidReleaseParameters.selector);

    bondedResponseModule.releaseUnutilizedResponse(mockRequest, _response);
  }

  /**
   * @notice Finalized request, disputed response, the call should revert if the dispute status is not Lost nor NoResolution
   */
  function test_withDisputedResponse(
    IERC20 _token,
    uint256 _bondSize,
    uint256 _deadline,
    address _proposer,
    bytes32 _finalizedResponseId,
    bytes32 _disputeId
  ) public {
    // Setting the response module data
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _baseDisputeWindow);

    // Updating IDs
    bytes32 _requestId = _getId(mockRequest);
    IOracle.Response memory _response = _getResponse(mockRequest, _proposer);
    bytes32 _responseId = _getId(_response);

    // Make sure there is a dispute
    vm.assume(_disputeId > 0);

    // Can't claim back the bond of the response that was finalized
    vm.assume(_finalizedResponseId > 0);
    vm.assume(_finalizedResponseId != _responseId);

    // Mock and expect IOracle.disputeOf to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeOf, (_responseId)), abi.encode(_disputeId));

    // Mock and expect IOracle.finalizedResponseId to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.finalizedResponseId, (_requestId)), abi.encode(_finalizedResponseId)
    );

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.responseCreatedAt, (_responseId)), abi.encode(block.timestamp)
    );

    // We're going to test all possible dispute statuses
    for (uint256 _i = 0; _i < uint256(type(IOracle.DisputeStatus).max); _i++) {
      IOracle.DisputeStatus _status = IOracle.DisputeStatus(_i);

      // Mock and expect IOracle.disputeOf to be called
      _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(_status));

      if (_status == IOracle.DisputeStatus.Lost || _status == IOracle.DisputeStatus.NoResolution) {
        // Mock and expect IAccountingExtension.release to be called
        _mockAndExpect(
          address(accounting),
          abi.encodeCall(IAccountingExtension.release, (_proposer, _getId(mockRequest), _token, _bondSize)),
          abi.encode(true)
        );
      } else {
        vm.expectRevert(IBondedResponseModule.BondedResponseModule_InvalidReleaseParameters.selector);
      }

      bondedResponseModule.releaseUnutilizedResponse(mockRequest, _response);
    }
  }
}
