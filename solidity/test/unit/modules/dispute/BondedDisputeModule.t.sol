// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IModule} from '@defi-wonderland/prophet-core/solidity/interfaces/IModule.sol';
import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

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

  event DisputeStatusChanged(bytes32 indexed _disputeId, IOracle.Dispute _dispute, IOracle.DisputeStatus _status);
  event ResponseDisputed(
    bytes32 indexed _requestId,
    bytes32 indexed _responseId,
    bytes32 indexed _disputeId,
    IOracle.Dispute _dispute,
    uint256 _blockNumber
  );

  /**
   * @notice Deploy the target and mock oracle
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    accountingExtension = IAccountingExtension(makeAddr('AccountingExtension'));
    vm.etch(address(accountingExtension), hex'069420');

    bondedDisputeModule = new BondedDisputeModule(oracle);
  }
}

contract BondedDisputeModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the decodeRequestData function returns the correct values
   */
  function test_decodeRequestData_returnsCorrectData(
    address _accountingExtension,
    address _token,
    uint256 _bondSize
  ) public {
    // Mock data
    bytes memory _requestData = abi.encode(_accountingExtension, _token, _bondSize);

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

  /**
   * @notice Test that the validateParameters function correctly checks the parameters
   */
  function test_validateParameters(IBondedDisputeModule.RequestParameters calldata _params) public {
    if (
      address(_params.accountingExtension) == address(0) || address(_params.bondToken) == address(0)
        || _params.bondSize == 0
    ) {
      assertFalse(bondedDisputeModule.validateParameters(abi.encode(_params)));
    } else {
      assertTrue(bondedDisputeModule.validateParameters(abi.encode(_params)));
    }
  }
}

contract BondedDisputeModule_Unit_OnDisputeStatusChange is BaseTest {
  /**
   * @notice Dispute lost by disputer
   */
  function test_paysProposer(uint256 _bondSize, IERC20 _token) public {
    mockRequest.disputeModuleData =
      abi.encode(IBondedDisputeModule.RequestParameters(accountingExtension, _token, _bondSize));
    bytes32 _requestId = _getId(mockRequest);
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(oracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Lost)
    );

    // Mock and expect the call to pay, from proposer to disputer
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeCall(
        accountingExtension.pay, (_requestId, mockDispute.disputer, mockResponse.proposer, _token, _bondSize)
      ),
      abi.encode()
    );

    // Mock and expect the call to release, to the disputer
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeCall(accountingExtension.release, (mockResponse.proposer, _requestId, _token, _bondSize)),
      abi.encode()
    );

    vm.prank(address(oracle));
    bondedDisputeModule.onDisputeStatusChange(_getId(mockDispute), mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Dispute won by disputer
   */
  function test_paysDisputer(uint256 _bondSize, IERC20 _token) public {
    mockRequest.disputeModuleData =
      abi.encode(IBondedDisputeModule.RequestParameters(accountingExtension, _token, _bondSize));
    bytes32 _requestId = _getId(mockRequest);
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(oracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Won)
    );

    // Mock and expect the call to pay, from disputer to proposer
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeCall(
        accountingExtension.pay, (_requestId, mockResponse.proposer, mockDispute.disputer, _token, _bondSize)
      ),
      abi.encode()
    );

    // Mock and expect the call to release, for the proposer
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeCall(accountingExtension.release, (mockDispute.disputer, _requestId, _token, _bondSize)),
      abi.encode()
    );

    vm.prank(address(oracle));
    bondedDisputeModule.onDisputeStatusChange(_getId(mockDispute), mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Dispute with no resolution
   */
  function test_refundsProposerAndDisputer(uint256 _bondSize, IERC20 _token) public {
    mockRequest.disputeModuleData =
      abi.encode(IBondedDisputeModule.RequestParameters(accountingExtension, _token, _bondSize));
    bytes32 _requestId = _getId(mockRequest);
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle),
      abi.encodeCall(oracle.disputeStatus, (_disputeId)),
      abi.encode(IOracle.DisputeStatus.NoResolution)
    );

    // Mock and expect the call to release, for the proposer
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeCall(accountingExtension.release, (mockResponse.proposer, _requestId, _token, _bondSize)),
      abi.encode()
    );

    // Mock and expect the call to release, for the disputer
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeCall(accountingExtension.release, (mockDispute.disputer, _requestId, _token, _bondSize)),
      abi.encode()
    );

    vm.prank(address(oracle));
    bondedDisputeModule.onDisputeStatusChange(_getId(mockDispute), mockRequest, mockResponse, mockDispute);
  }

  function test_statusWithNoChange(uint256 _bondSize, IERC20 _token) public {
    // Mock request data
    mockRequest.disputeModuleData =
      abi.encode(IBondedDisputeModule.RequestParameters(accountingExtension, _token, _bondSize));
    mockDispute.requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(mockDispute);

    for (uint256 _status; _status < 1; _status++) {
      // Mock and expect IOracle.disputeStatus to be called
      _mockAndExpect(
        address(oracle), abi.encodeCall(oracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus(_status))
      );

      // Expect the event
      vm.expectEmit(true, true, true, true, address(bondedDisputeModule));
      emit DisputeStatusChanged(_disputeId, mockDispute, IOracle.DisputeStatus(_status));

      vm.prank(address(oracle));
      bondedDisputeModule.onDisputeStatusChange(_disputeId, mockRequest, mockResponse, mockDispute);
    }
  }

  /**
   * @notice Test if onDisputeStatusChange reverts when called by caller who's not the oracle
   */
  function test_revertWrongCaller(address _randomCaller) public {
    vm.assume(_randomCaller != address(oracle));

    // Check: revert if wrong caller
    vm.expectRevert(IModule.Module_OnlyOracle.selector);

    // Test: call disputeResponse from non-oracle address
    vm.prank(_randomCaller);
    bondedDisputeModule.onDisputeStatusChange(_getId(mockDispute), mockRequest, mockResponse, mockDispute);
  }
}

contract BondedDisputeModule_Unit_DisputeResponse is BaseTest {
  /**
   * @notice Test if dispute response returns the correct status
   */
  function test_createBond(uint256 _bondSize, IERC20 _token) public {
    // Mock request data
    mockRequest.disputeModuleData =
      abi.encode(IBondedDisputeModule.RequestParameters(accountingExtension, _token, _bondSize));
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;
    mockDispute.requestId = _requestId;
    mockDispute.responseId = _getId(mockResponse);

    // Mock and expect the call to the accounting extension, initiating the bond
    _mockAndExpect(
      address(accountingExtension),
      abi.encodeWithSignature(
        'bond(address,bytes32,address,uint256)', mockDispute.disputer, _requestId, _token, _bondSize
      ),
      abi.encode()
    );

    // Expect the event
    vm.expectEmit(true, true, true, true, address(bondedDisputeModule));
    emit ResponseDisputed(_requestId, _getId(mockResponse), _getId(mockDispute), mockDispute, block.number);

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
    vm.expectRevert(IModule.Module_OnlyOracle.selector);

    // Test: call disputeResponse from non-oracle address
    vm.prank(_randomCaller);
    bondedDisputeModule.disputeResponse(mockRequest, mockResponse, mockDispute);
  }
}
