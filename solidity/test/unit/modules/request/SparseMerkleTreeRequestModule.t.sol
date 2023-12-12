// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IModule} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IModule.sol';

import {
  SparseMerkleTreeRequestModule,
  ISparseMerkleTreeRequestModule
} from '../../../../contracts/modules/request/SparseMerkleTreeRequestModule.sol';

import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';
import {ITreeVerifier} from '../../../../interfaces/ITreeVerifier.sol';

/**
 * @title Sparse Merkle Tree Request Module Unit tests
 */
contract BaseTest is Test, Helpers {
  // The target contract
  SparseMerkleTreeRequestModule public sparseMerkleTreeRequestModule;
  // A mock oracle
  IOracle public oracle;

  // Mock data for the request
  bytes32[32] internal _treeBranches = [
    bytes32('branch1'),
    bytes32('branch2'),
    bytes32('branch3'),
    bytes32('branch4'),
    bytes32('branch5'),
    bytes32('branch6'),
    bytes32('branch7'),
    bytes32('branch8'),
    bytes32('branch9'),
    bytes32('branch10'),
    bytes32('branch11'),
    bytes32('branch12'),
    bytes32('branch13'),
    bytes32('branch14'),
    bytes32('branch15'),
    bytes32('branch16'),
    bytes32('branch17'),
    bytes32('branch18'),
    bytes32('branch19'),
    bytes32('branch20'),
    bytes32('branch21'),
    bytes32('branch22'),
    bytes32('branch23'),
    bytes32('branch24'),
    bytes32('branch25'),
    bytes32('branch26'),
    bytes32('branch27'),
    bytes32('branch28'),
    bytes32('branch29'),
    bytes32('branch30'),
    bytes32('branch31'),
    bytes32('branch32')
  ];
  uint256 internal _treeCount = 1;
  bytes internal _treeData = abi.encode(_treeBranches, _treeCount);
  bytes32[] internal _leavesToInsert = [bytes32('leave1'), bytes32('leave2')];

  /**
   * @notice Deploy the target and mock oracle+accounting extension
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    sparseMerkleTreeRequestModule = new SparseMerkleTreeRequestModule(oracle);
  }
}

contract SparseMerkleTreeRequestModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleNameReturnsName() public {
    assertEq(sparseMerkleTreeRequestModule.moduleName(), 'SparseMerkleTreeRequestModule', 'Wrong module name');
  }

  /**
   * @notice Test that the decodeRequestData function returns the correct values
   */
  function test_decodeRequestData(
    IERC20 _paymentToken,
    uint256 _paymentAmount,
    IAccountingExtension _accounting,
    ITreeVerifier _treeVerifier
  ) public {
    bytes memory _requestData = abi.encode(
      ISparseMerkleTreeRequestModule.RequestParameters({
        treeData: _treeData,
        leavesToInsert: _leavesToInsert,
        treeVerifier: _treeVerifier,
        accountingExtension: _accounting,
        paymentToken: _paymentToken,
        paymentAmount: _paymentAmount
      })
    );

    // Decode the given request data
    ISparseMerkleTreeRequestModule.RequestParameters memory _params =
      sparseMerkleTreeRequestModule.decodeRequestData(_requestData);

    (bytes32[32] memory _decodedTreeBranches, uint256 _decodedTreeCount) =
      abi.decode(_params.treeData, (bytes32[32], uint256));

    // Check: decoded values match original values?
    for (uint256 _i = 0; _i < _treeBranches.length; _i++) {
      assertEq(_decodedTreeBranches[_i], _treeBranches[_i], 'Mismatch: decoded tree branch');
    }
    for (uint256 _i = 0; _i < _leavesToInsert.length; _i++) {
      assertEq(_params.leavesToInsert[_i], _leavesToInsert[_i], 'Mismatch: decoded leave to insert');
    }
    assertEq(_decodedTreeCount, _treeCount, 'Mismatch: decoded tree count');
    assertEq(address(_params.treeVerifier), address(_treeVerifier), 'Mismatch: decoded tree verifier');
    assertEq(address(_params.accountingExtension), address(_accounting), 'Mismatch: decoded accounting extension');
    assertEq(address(_params.paymentToken), address(_paymentToken), 'Mismatch: decoded payment token');
    assertEq(_params.paymentAmount, _paymentAmount, 'Mismatch: decoded payment amount');
  }
}

contract SparseMerkleTreeRequestModule_Unit_FinalizeRequest is BaseTest {
  /**
   * @notice Test that the proposer gets paid for a correct response
   */
  function test_paysProposer(
    IERC20 _paymentToken,
    uint256 _paymentAmount,
    IAccountingExtension _accounting,
    ITreeVerifier _treeVerifier
  ) public assumeFuzzable(address(_accounting)) {
    // Use the correct accounting parameters
    mockRequest.requestModuleData = abi.encode(
      ISparseMerkleTreeRequestModule.RequestParameters({
        treeData: _treeData,
        leavesToInsert: _leavesToInsert,
        treeVerifier: _treeVerifier,
        accountingExtension: _accounting,
        paymentToken: _paymentToken,
        paymentAmount: _paymentAmount
      })
    );

    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;

    // Oracle confirms that the response has been created
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.createdAt, (_getId(mockResponse))), abi.encode(block.timestamp)
    );

    // Mock and expect IAccountingExtension.pay to be called
    _mockAndExpect(
      address(_accounting),
      abi.encodeCall(
        IAccountingExtension.pay,
        (_requestId, mockRequest.requester, mockResponse.proposer, _paymentToken, _paymentAmount)
      ),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(sparseMerkleTreeRequestModule));
    emit RequestFinalized(_requestId, mockResponse, address(this));

    vm.prank(address(oracle));
    sparseMerkleTreeRequestModule.finalizeRequest(mockRequest, mockResponse, address(this));
  }

  /**
   * @notice Test that the requester gets a refund in case of no responses
   */
  function test_refundsRequester(
    IERC20 _paymentToken,
    uint256 _paymentAmount,
    IAccountingExtension _accounting,
    ITreeVerifier _treeVerifier
  ) public assumeFuzzable(address(_accounting)) {
    // Use the correct accounting parameters
    mockRequest.requestModuleData = abi.encode(
      ISparseMerkleTreeRequestModule.RequestParameters({
        treeData: _treeData,
        leavesToInsert: _leavesToInsert,
        treeVerifier: _treeVerifier,
        accountingExtension: _accounting,
        paymentToken: _paymentToken,
        paymentAmount: _paymentAmount
      })
    );

    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;

    // Oracle returns no createdAt value - finalizing without a response
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.createdAt, (_getId(mockResponse))), abi.encode(0));

    // Mock and expect IAccountingExtension.release to be called
    _mockAndExpect(
      address(_accounting),
      abi.encodeCall(IAccountingExtension.release, (mockRequest.requester, _requestId, _paymentToken, _paymentAmount)),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(sparseMerkleTreeRequestModule));
    emit RequestFinalized(_requestId, mockResponse, address(this));

    vm.prank(address(oracle));
    sparseMerkleTreeRequestModule.finalizeRequest(mockRequest, mockResponse, address(this));
  }

  /**
   * @notice Test that the finalizeRequest reverts if caller is not the oracle
   */
  function test_revertsIfWrongCaller(address _caller) public {
    vm.assume(_caller != address(oracle));

    // Check: does it revert if not called by the Oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);

    vm.prank(_caller);
    sparseMerkleTreeRequestModule.finalizeRequest(mockRequest, mockResponse, address(_caller));
  }
}
