// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {
  IRootVerificationModule, RootVerificationModule
} from '../../contracts/modules/dispute/RootVerificationModule.sol';
import {
  ISparseMerkleTreeRequestModule,
  SparseMerkleTreeRequestModule
} from '../../contracts/modules/request/SparseMerkleTreeRequestModule.sol';
import {SparseMerkleTreeL32Verifier} from '../../contracts/periphery/SparseMerkleTreeL32Verifier.sol';
import {ITreeVerifier} from '../../interfaces/ITreeVerifier.sol';
import './IntegrationBase.sol';

contract Integration_RootVerification is IntegrationBase {
  SparseMerkleTreeL32Verifier internal _treeVerifier;

  bytes32 internal _requestId;
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
  bytes32 internal _correctRoot;

  function setUp() public override {
    super.setUp();

    SparseMerkleTreeRequestModule _sparseMerkleTreeModule = new SparseMerkleTreeRequestModule(oracle);
    label(address(_sparseMerkleTreeModule), 'SparseMerkleTreeModule');

    RootVerificationModule _rootVerificationModule = new RootVerificationModule(oracle);
    label(address(_rootVerificationModule), 'RootVerificationModule');

    _treeVerifier = new SparseMerkleTreeL32Verifier();
    label(address(_treeVerifier), 'TreeVerifier');

    mockRequest.requestModuleData = abi.encode(
      ISparseMerkleTreeRequestModule.RequestParameters({
        treeData: _treeData,
        leavesToInsert: _leavesToInsert,
        treeVerifier: ITreeVerifier(_treeVerifier),
        accountingExtension: _accountingExtension,
        paymentToken: usdc,
        paymentAmount: _expectedReward
      })
    );

    mockRequest.disputeModuleData = abi.encode(
      IRootVerificationModule.RequestParameters({
        treeData: _treeData,
        leavesToInsert: _leavesToInsert,
        treeVerifier: ITreeVerifier(_treeVerifier),
        accountingExtension: _accountingExtension,
        bondToken: usdc,
        bondSize: _expectedBondSize
      })
    );

    mockRequest.requestModule = address(_sparseMerkleTreeModule);
    mockRequest.disputeModule = address(_rootVerificationModule);

    _resetMockIds();

    _deposit(_accountingExtension, requester, usdc, _expectedReward);

    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_sparseMerkleTreeModule));
    _requestId = oracle.createRequest(mockRequest, _ipfsHash);
    vm.stopPrank();

    vm.prank(proposer);
    _accountingExtension.approveModule(address(_responseModule));

    _correctRoot = ITreeVerifier(_treeVerifier).calculateRoot(_treeData, _leavesToInsert);
  }

  function test_validResponse() public {
    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);

    mockResponse.response = abi.encode(_correctRoot);

    vm.prank(proposer);
    oracle.proposeResponse(mockRequest, mockResponse);

    vm.roll(_expectedDeadline + _baseDisputeWindow);

    oracle.finalize(mockRequest, mockResponse);
  }

  function test_disputeResponse_incorrectResponse(bytes32 _invalidRoot) public {
    vm.assume(_correctRoot != _invalidRoot);

    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);

    mockResponse.response = abi.encode(_invalidRoot);

    vm.prank(proposer);
    oracle.proposeResponse(mockRequest, mockResponse);
    _resetMockIds();

    vm.startPrank(disputer);
    _accountingExtension.approveModule(address(_responseModule));
    _accountingExtension.approveModule(address(mockRequest.disputeModule));
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);
    vm.stopPrank();

    uint256 _requesterBondedBalance = _accountingExtension.bondedAmountOf(requester, usdc, _requestId);
    assertEq(_requesterBondedBalance, 0);

    uint256 _proposerBondedBalance = _accountingExtension.bondedAmountOf(proposer, usdc, _requestId);
    assertEq(_proposerBondedBalance, 0);

    uint256 _requesterVirtualBalance = _accountingExtension.balanceOf(requester, usdc);
    assertEq(_requesterVirtualBalance, 0);

    uint256 _proposerVirtualBalance = _accountingExtension.balanceOf(proposer, usdc);
    assertEq(_proposerVirtualBalance, 0);

    uint256 _disputerVirtualBalance = _accountingExtension.balanceOf(disputer, usdc);
    assertEq(_disputerVirtualBalance, _expectedBondSize + _expectedReward);
  }

  function test_disputeResponse_correctResponse() public {
    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);

    mockResponse.response = abi.encode(_correctRoot);

    vm.prank(proposer);
    oracle.proposeResponse(mockRequest, mockResponse);
    _resetMockIds();

    vm.startPrank(disputer);
    _accountingExtension.approveModule(address(_responseModule));
    oracle.disputeResponse(mockRequest, mockResponse, mockDispute);
    vm.stopPrank();

    assertEq(_accountingExtension.bondedAmountOf(requester, usdc, _requestId), 0);
    assertEq(_accountingExtension.bondedAmountOf(proposer, usdc, _requestId), 0);
    assertEq(_accountingExtension.balanceOf(requester, usdc), 0);
    assertEq(_accountingExtension.balanceOf(proposer, usdc), _expectedBondSize + _expectedReward);
  }
}
