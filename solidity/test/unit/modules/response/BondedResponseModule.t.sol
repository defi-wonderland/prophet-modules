// SPDX-License-Identifier: AGPL-3.0-only
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

  // Events
  event ResponseProposed(bytes32 indexed _requestId, IOracle.Response _response, uint256 indexed _blockNumber);

  /**
   * @notice Deploy the target and mock oracle+accounting extension
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    // Avoid starting at 0 for time sensitive tests
    vm.warp(123_456);

    bondedResponseModule = new BondedResponseModule(oracle);
  }
}

contract BondedResponseModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleNameReturnsName() public {
    assertEq(bondedResponseModule.moduleName(), 'BondedResponseModule');
  }

  /**
   * @notice Test that the decodeRequestData function returns the correct values
   */
  function test_decodeRequestData(IERC20 _token, uint256 _bondSize, uint256 _deadline, uint256 _disputeWindow) public {
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
}

contract BondedResponseModule_Unit_Propose is BaseTest {
  /**
   * @notice Test that the propose function is only callable by the oracle
   */
  function test_revertIfNotOracle(address _sender) public {
    vm.assume(_sender != address(oracle));

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(abi.encodeWithSelector(IModule.Module_OnlyOracle.selector));

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
    address _sender,
    address _proposer
  ) public assumeFuzzable(_sender) assumeFuzzable(_proposer) {
    _deadline = bound(_deadline, block.timestamp + 1, type(uint248).max);
    _disputeWindow = bound(_disputeWindow, 61, 365 days);
    _bondSize = bound(_bondSize, 0, type(uint248).max);

    // Set the response module parameters
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);

    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;
    mockResponse.proposer = _proposer;

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

  function test_emitsEvent(
    IERC20 _token,
    uint256 _bondSize,
    uint256 _deadline,
    uint256 _disputeWindow,
    address _sender,
    address _proposer
  ) public {
    _deadline = bound(_deadline, block.timestamp + 1, type(uint248).max);
    _disputeWindow = bound(_disputeWindow, 61, 365 days);

    // Create and set some mock request data
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;
    mockResponse.proposer = _proposer;

    // Mock and expect IOracle.getResponseIds to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.getResponseIds, _requestId), abi.encode(new bytes32[](0)));

    // Mock and expect IOracle.getResponseIds to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeWithSignature(
        'bond(address,bytes32,address,uint256,address)', _proposer, _requestId, _token, _bondSize, _sender
      ),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(bondedResponseModule));
    emit ResponseProposed({_requestId: _requestId, _response: mockResponse, _blockNumber: block.number});

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
    vm.expectRevert(abi.encodeWithSelector(IModule.Module_OnlyOracle.selector));

    vm.prank(address(_sender));
    bondedResponseModule.finalizeRequest(mockRequest, mockResponse, _sender);
  }

  function test_revertsBeforeDeadline(
    IERC20 _token,
    uint256 _bondSize,
    uint256 _deadline,
    uint256 _disputeWindow,
    address _proposer
  ) public {
    _deadline = bound(_deadline, block.timestamp + 1, type(uint248).max);
    _disputeWindow = bound(_disputeWindow, 61, 365 days);

    // Check revert if deadline has not passed
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);
    mockResponse.requestId = _getId(mockRequest);
    mockResponse.proposer = _proposer;

    // Mock and expect IOracle.allowedModule to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_getId(mockRequest), address(this))), abi.encode(false)
    );

    // Check: does it revert if it's too early to finalize?
    vm.expectRevert(IBondedResponseModule.BondedResponseModule_TooEarlyToFinalize.selector);

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
    _deadline = block.timestamp;
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);
    mockResponse.requestId = _getId(mockRequest);
    mockResponse.proposer = _proposer;

    // Mock and expect IOracle.allowedModule to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_getId(mockRequest), address(this))), abi.encode(true)
    );

    // Mock and expect IOracle.createdAt to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.createdAt, (_getId(mockResponse))), abi.encode(block.timestamp)
    );

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_proposer, _getId(mockRequest), _token, _bondSize)),
      abi.encode(true)
    );

    vm.warp(block.timestamp + _disputeWindow);

    vm.prank(address(oracle));
    bondedResponseModule.finalizeRequest(mockRequest, mockResponse, address(this));
  }

  function test_emitsEvent(IERC20 _token, uint256 _bondSize, uint256 _disputeWindow, address _proposer) public {
    _disputeWindow = bound(_disputeWindow, 61, 365 days);

    // Check correct calls are made if deadline has passed
    uint256 _deadline = block.number;
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _disputeWindow);
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;
    mockResponse.proposer = _proposer;

    // Mock and expect IOracle.allowedModule to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, address(this))), abi.encode(false)
    );

    // Mock and expect IOracle.createdAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.createdAt, (_getId(mockResponse))), abi.encode(block.number));

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IAccountingExtension.release, (_proposer, _getId(mockRequest), _token, _bondSize)),
      abi.encode(true)
    );

    // Check: is event emitted?
    vm.expectEmit(true, true, true, true, address(bondedResponseModule));
    emit RequestFinalized({_requestId: _getId(mockRequest), _response: mockResponse, _finalizer: address(this)});

    vm.roll(block.number + _disputeWindow);

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
    _deadline = bound(_deadline, block.timestamp + 1, type(uint248).max);
    mockRequest.responseModuleData = abi.encode(accounting, _token, _bondSize, _deadline, _baseDisputeWindow);

    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;
    mockResponse.proposer = _proposer;

    // Mock and expect IOracle.allowedModule to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.allowedModule, (_requestId, _allowedModule)), abi.encode(true)
    );

    // Mock and expect IOracle.createdAt to be called
    _mockAndExpect(
      address(oracle),
      abi.encodeCall(IOracle.createdAt, (_getId(mockResponse))),
      abi.encode(block.timestamp - _baseDisputeWindow)
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

    vm.expectRevert(IBondedResponseModule.BondedResponseModule_TooEarlyToFinalize.selector);

    vm.prank(address(oracle));
    bondedResponseModule.finalizeRequest(mockRequest, mockResponse, _finalizer);
  }
}
