// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IModule} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IModule.sol';

import {
  BondedDisputeModule, IBondedDisputeModule
} from '../../../../contracts/modules/dispute/BondedDisputeModule.sol';

import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';

/**
 * @title Bonded Dispute Module Unit tests
 */
contract BaseTest is Test, Helpers {
  // The target contract
  BondedDisputeModule public bondedDisputeModule;
  // A mock accounting extension
  IAccountingExtension public accountingExtension;
  // A mock oracle
  IOracle public oracle;
  // Some unnoticeable dude
  address public dude = makeAddr('dude');
  // 100% random sequence of bytes representing request, response, or dispute id
  bytes32 public mockId = bytes32('69');
  // Create a dummy request
  IOracle.Request public mockRequest;
  // Create a dummy response
  IOracle.Response public mockResponse;
  // Create a dummy dispute
  IOracle.Dispute public mockDispute;

  event DisputeStatusChanged(bytes32 indexed _disputeId, IOracle.Dispute _dispute, IOracle.DisputeStatus _status);
  // TODO: event ResponseDisputed(bytes32 indexed _requestId, bytes32 indexed _responseId, IOracle.Dispute _dispute, uint256 _blockNumber);

  /**
   * @notice Deploy the target and mock oracle
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    accountingExtension = IAccountingExtension(makeAddr('AccountingExtension'));
    vm.etch(address(accountingExtension), hex'069420');

    bondedDisputeModule = new BondedDisputeModule(oracle);

    mockDispute = IOracle.Dispute({disputer: dude, proposer: dude, responseId: mockId, requestId: mockId});
  }
}

contract BondedResponseModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the decodeRequestData function returns the correct values
   */
  function test_decodeRequestData_returnsCorrectData(
    bytes32 _requestId,
    address _accountingExtension,
    address _token,
    uint256 _bondSize
  ) public {
    // Mock data
    bytes memory _requestData = abi.encode(_accountingExtension, _token, _bondSize);

    // Store the mock request
    // bondedDisputeModule.forTest_setRequestData(_requestId, _requestData);

    // Test: decode the given request data
    IBondedDisputeModule.RequestParameters memory _storedParams = bondedDisputeModule.decodeRequestData(_requestData);

    // Check: decoded values match original values?
    assertEq(address(_storedParams.accountingExtension), _accountingExtension);
    assertEq(address(_storedParams.bondToken), _token);
    assertEq(_storedParams.bondSize, _bondSize);
  }

  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleNameReturnsName() public {
    assertEq(bondedDisputeModule.moduleName(), 'BondedDisputeModule');
  }
}

contract BondedResponseModule_Unit_OnDisputeStatusChange is BaseTest {
  /**
   * @notice Test if onDisputeStatusChange correctly handle proposer or disputer win
   */
  function test_correctWinnerPaid(uint256 _bondSize, address _disputer, address _proposer, IERC20 _token) public {
    // Mock id's (insure they are different)
    bytes32 _requestId = mockId;
    bytes32 _responseId = bytes32(uint256(mockId) + 1);

    // Mock request data
    bytes memory _requestData = abi.encode(accountingExtension, _token, _bondSize);

    // Store the mock request
    // bondedDisputeModule.forTest_setRequestData(mockId, _requestData);

    // ------------------------------------
    //   Scenario: dispute won by proposer
    // ------------------------------------

    mockDispute =
      IOracle.Dispute({disputer: _disputer, proposer: _proposer, responseId: _responseId, requestId: _requestId});

    // Mock and expect the call to pay, from¨*proposer to disputer*
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeCall(accountingExtension.pay, (_requestId, _proposer, _disputer, _token, _bondSize)),
      abi.encode()
    );

    // Mock and expect the call to release, to the disputer
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeCall(accountingExtension.release, (_disputer, _requestId, _token, _bondSize)),
      abi.encode()
    );

    vm.prank(address(oracle));
    bondedDisputeModule.onDisputeStatusChange(mockId, mockRequest, mockResponse, mockDispute);

    // ------------------------------------
    //   Scenario: dispute loss by proposer
    // ------------------------------------

    mockDispute =
      IOracle.Dispute({disputer: _disputer, proposer: _proposer, responseId: _responseId, requestId: _requestId});

    // Mock and expect the call to pay, from *disputer to proposer*
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeCall(accountingExtension.pay, (_requestId, _disputer, _proposer, _token, _bondSize)),
      abi.encode()
    );

    // Mock and expect the call to release, for the proposer
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeCall(accountingExtension.release, (_proposer, _requestId, _token, _bondSize)),
      abi.encode()
    );

    vm.prank(address(oracle));
    bondedDisputeModule.onDisputeStatusChange(mockId, mockRequest, mockResponse, mockDispute);

    // ------------------------------------
    //   Scenario: dispute with no resolution
    // ------------------------------------

    mockDispute =
      IOracle.Dispute({disputer: _disputer, proposer: _proposer, responseId: _responseId, requestId: _requestId});

    // Mock and expect the call to release, for the proposer
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeCall(accountingExtension.release, (_proposer, _requestId, _token, _bondSize)),
      abi.encode()
    );

    // Mock and expect the call to release, for the disputer
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeCall(accountingExtension.release, (_disputer, _requestId, _token, _bondSize)),
      abi.encode()
    );

    vm.prank(address(oracle));
    bondedDisputeModule.onDisputeStatusChange(mockId, mockRequest, mockResponse, mockDispute);
  }

  function test_statusWithNoChange(uint256 _bondSize, address _disputer, address _proposer, IERC20 _token) public {
    // Mock id's (insure they are different)
    bytes32 _requestId = mockId;
    bytes32 _responseId = bytes32(uint256(mockId) + 1);

    // Mock request data
    bytes memory _requestData = abi.encode(accountingExtension, _token, _bondSize);

    // Store the mock request
    // bondedDisputeModule.forTest_setRequestData(mockId, _requestData);

    // ------------------------------------
    //   Scenario: dispute new status is None
    // ------------------------------------

    mockDispute =
      IOracle.Dispute({disputer: _disputer, proposer: _proposer, responseId: _responseId, requestId: _requestId});

    // Expect the event
    vm.expectEmit(true, true, true, true, address(bondedDisputeModule));
    emit DisputeStatusChanged(_requestId, _responseId, _disputer, _proposer, IOracle.DisputeStatus.None);

    vm.prank(address(oracle));
    bondedDisputeModule.onDisputeStatusChange(mockId, mockRequest, mockResponse, mockDispute);

    // ------------------------------------
    //   Scenario: dispute new status is Active
    // ------------------------------------

    mockDispute =
      IOracle.Dispute({disputer: _disputer, proposer: _proposer, responseId: _responseId, requestId: _requestId});

    // Expect the event
    vm.expectEmit(true, true, true, true, address(bondedDisputeModule));
    emit DisputeStatusChanged(_requestId, _responseId, _disputer, _proposer, IOracle.DisputeStatus.Active);

    vm.prank(address(oracle));
    bondedDisputeModule.onDisputeStatusChange(mockId, mockRequest, mockResponse, mockDispute);
    // ------------------------------------
    //   Scenario: dispute new status is Escalated
    // ------------------------------------

    mockDispute =
      IOracle.Dispute({disputer: _disputer, proposer: _proposer, responseId: _responseId, requestId: _requestId});

    // Expect the event
    vm.expectEmit(true, true, true, true, address(bondedDisputeModule));
    emit DisputeStatusChanged(_requestId, _responseId, _disputer, _proposer, IOracle.DisputeStatus.Escalated);

    vm.prank(address(oracle));
    bondedDisputeModule.onDisputeStatusChange(mockId, mockRequest, mockResponse, mockDispute);
  }

  function test_emitsEvent(uint256 _bondSize, address _disputer, address _proposer, IERC20 _token) public {
    // Mock id's (insure they are different)
    bytes32 _requestId = mockId;
    bytes32 _responseId = bytes32(uint256(mockId) + 1);

    // Mock request data
    bytes memory _requestData = abi.encode(accountingExtension, _token, _bondSize);

    // Store the mock request
    // bondedDisputeModule.forTest_setRequestData(mockId, _requestData);

    // ------------------------------------
    //   Scenario: dispute won by proposer
    // ------------------------------------

    mockDispute =
      IOracle.Dispute({disputer: _disputer, proposer: _proposer, responseId: _responseId, requestId: _requestId});

    // Mock and expect the call to pay, from¨*proposer to disputer*
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeCall(accountingExtension.pay, (_requestId, _proposer, _disputer, _token, _bondSize)),
      abi.encode()
    );

    // Mock and expect the call to release, to the disputer
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeCall(accountingExtension.release, (_disputer, _requestId, _token, _bondSize)),
      abi.encode()
    );

    // Expect the event
    vm.expectEmit(true, true, true, true, address(bondedDisputeModule));
    emit DisputeStatusChanged(_requestId, _responseId, _disputer, _proposer, IOracle.DisputeStatus.Won);

    vm.prank(address(oracle));
    bondedDisputeModule.onDisputeStatusChange(mockId, mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Test if onDisputeStatusChange reverts when called by caller who's not the oracle
   */
  function test_revertWrongCaller(address _randomCaller) public {
    vm.assume(_randomCaller != address(oracle));

    // Check: revert if wrong caller
    vm.expectRevert(abi.encodeWithSelector(IModule.Module_OnlyOracle.selector));

    // Test: call disputeResponse from non-oracle address
    vm.prank(_randomCaller);
    bondedDisputeModule.onDisputeStatusChange(mockId, mockRequest, mockResponse, mockDispute);
  }
}

contract BondedResponseModule_Unit_DisputeResponse is BaseTest {
  /**
   * @notice Test if dispute response returns the correct status
   */
  function test_createBond(uint256 _bondSize, address _disputer, address _proposer, IERC20 _token) public {
    // Mock id's (insure they are different)
    bytes32 _requestId = mockId;
    bytes32 _responseId = bytes32(uint256(mockId) + 1);

    // Mock request data
    bytes memory _requestData = abi.encode(accountingExtension, _token, _bondSize);

    // Store the mock request
    // bondedDisputeModule.forTest_setRequestData(mockId, _requestData);

    // Mock and expect the call to the accounting extension, initiating the bond
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeWithSignature('bond(address,bytes32,address,uint256)', _disputer, _requestId, _token, _bondSize),
      abi.encode()
    );

    // Test: call disputeResponse
    vm.prank(address(oracle));
    bondedDisputeModule.disputeResponse(mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Test if dispute response reverts when called by caller who's not the oracle
   */
  function test_revertWrongCaller(address _randomCaller) public {
    vm.assume(_randomCaller != address(oracle));

    // Check: revert if wrong caller
    vm.expectRevert(abi.encodeWithSelector(IModule.Module_OnlyOracle.selector));

    // Test: call disputeResponse from non-oracle address
    vm.prank(_randomCaller);
    bondedDisputeModule.disputeResponse(mockRequest, mockResponse, mockDispute);
  }
}
