// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './IntegrationBase.sol';
import {
  SparseMerkleTreeRequestModule,
  ISparseMerkleTreeRequestModule,
  IOracle
} from '../../contracts/modules/request/SparseMerkleTreeRequestModule.sol';
import {SparseMerkleTreeL32Verifier} from '../../contracts/periphery/SparseMerkleTreeL32Verifier.sol';
import {
  RootVerificationModule, IRootVerificationModule
} from '../../contracts/modules/dispute/RootVerificationModule.sol';
import {ITreeVerifier} from '../../interfaces/ITreeVerifier.sol';

contract Integration_RootVerification is IntegrationBase {
  SparseMerkleTreeL32Verifier internal _treeVerifier;

  IOracle.Request internal _request;
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

  function setUp() public override {
    super.setUp();
    _expectedDeadline = block.timestamp + BLOCK_TIME * 600;

    SparseMerkleTreeRequestModule _sparseMerkleTreeModule = new SparseMerkleTreeRequestModule(oracle);
    label(address(_sparseMerkleTreeModule), 'SparseMerkleTreeModule');

    RootVerificationModule _rootVerificationModule = new RootVerificationModule(oracle);
    label(address(_rootVerificationModule), 'RootVerificationModule');

    _treeVerifier = new SparseMerkleTreeL32Verifier();
    label(address(_treeVerifier), 'TreeVerifier');

    _request = IOracle.Request({
      nonce: 0,
      requester: requester,
      requestModuleData: abi.encode(
        ISparseMerkleTreeRequestModule.RequestParameters({
          treeData: _treeData,
          leavesToInsert: _leavesToInsert,
          treeVerifier: ITreeVerifier(_treeVerifier),
          accountingExtension: _accountingExtension,
          paymentToken: IERC20(USDC_ADDRESS),
          paymentAmount: _expectedReward
        })
        ),
      responseModuleData: abi.encode(
        IBondedResponseModule.RequestParameters({
          accountingExtension: _accountingExtension,
          bondToken: IERC20(USDC_ADDRESS),
          bondSize: _expectedBondSize,
          deadline: _expectedDeadline,
          disputeWindow: _baseDisputeWindow
        })
        ),
      disputeModuleData: abi.encode(
        IRootVerificationModule.RequestParameters({
          treeData: _treeData,
          leavesToInsert: _leavesToInsert,
          treeVerifier: ITreeVerifier(_treeVerifier),
          accountingExtension: _accountingExtension,
          bondToken: IERC20(USDC_ADDRESS),
          bondSize: _expectedBondSize
        })
        ),
      resolutionModuleData: abi.encode(_mockArbitrator),
      finalityModuleData: abi.encode(
        ICallbackModule.RequestParameters({target: address(_mockCallback), data: abi.encode(_expectedCallbackValue)})
        ),
      requestModule: address(_sparseMerkleTreeModule),
      responseModule: address(_responseModule),
      disputeModule: address(_rootVerificationModule),
      resolutionModule: address(_arbitratorModule),
      finalityModule: address(_callbackModule)
    });

    _forBondDepositERC20(_accountingExtension, requester, usdc, _expectedReward, _expectedReward);

    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_sparseMerkleTreeModule));
    _requestId = oracle.createRequest(_request, _ipfsHash);
    vm.stopPrank();
  }

  function test_validResponse() public {
    bytes32 _correctRoot = ITreeVerifier(_treeVerifier).calculateRoot(_treeData, _leavesToInsert);

    _forBondDepositERC20(_accountingExtension, proposer, usdc, _expectedBondSize, _expectedBondSize);

    IOracle.Response memory _response =
      IOracle.Response({proposer: proposer, requestId: _requestId, response: abi.encode(_correctRoot)});

    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    oracle.proposeResponse(_request, _response);
    vm.stopPrank();

    vm.roll(_expectedDeadline + _baseDisputeWindow);

    oracle.finalize(_request, _response);
  }

  function test_disputeResponse_incorrectResponse(bytes32 _invalidRoot) public {
    bytes32 _correctRoot = ITreeVerifier(_treeVerifier).calculateRoot(_treeData, _leavesToInsert);
    vm.assume(_correctRoot != _invalidRoot);

    _forBondDepositERC20(_accountingExtension, proposer, usdc, _expectedBondSize, _expectedBondSize);

    IOracle.Response memory _response =
      IOracle.Response({proposer: proposer, requestId: _requestId, response: abi.encode(_invalidRoot)});

    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    bytes32 _responseId = oracle.proposeResponse(_request, _response);
    vm.stopPrank();

    IOracle.Dispute memory _dispute =
      IOracle.Dispute({proposer: proposer, disputer: disputer, requestId: _requestId, responseId: _responseId});

    vm.startPrank(disputer);
    _accountingExtension.approveModule(address(_responseModule));
    oracle.disputeResponse(_request, _response, _dispute);
    vm.stopPrank();

    uint256 _requesterBondedBalance = _accountingExtension.bondedAmountOf(requester, usdc, _requestId);
    uint256 _proposerBondedBalance = _accountingExtension.bondedAmountOf(proposer, usdc, _requestId);

    uint256 _requesterVirtualBalance = _accountingExtension.balanceOf(requester, usdc);
    uint256 _proposerVirtualBalance = _accountingExtension.balanceOf(proposer, usdc);
    uint256 _disputerVirtualBalance = _accountingExtension.balanceOf(disputer, usdc);

    assertEq(_requesterBondedBalance, 0);
    assertEq(_proposerBondedBalance, 0);

    assertEq(_requesterVirtualBalance, 0);
    assertEq(_proposerVirtualBalance, 0);
    assertEq(_disputerVirtualBalance, _expectedBondSize + _expectedReward);
  }

  function test_disputeResponse_correctResponse() public {
    bytes32 _correctRoot = ITreeVerifier(_treeVerifier).calculateRoot(_treeData, _leavesToInsert);

    _forBondDepositERC20(_accountingExtension, proposer, usdc, _expectedBondSize, _expectedBondSize);

    IOracle.Response memory _response =
      IOracle.Response({proposer: proposer, requestId: _requestId, response: abi.encode(_correctRoot)});

    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    bytes32 _responseId = oracle.proposeResponse(_request, _response);
    vm.stopPrank();

    IOracle.Dispute memory _dispute =
      IOracle.Dispute({proposer: proposer, disputer: disputer, requestId: _requestId, responseId: _responseId});

    vm.startPrank(disputer);
    _accountingExtension.approveModule(address(_responseModule));
    oracle.disputeResponse(_request, _response, _dispute);
    vm.stopPrank();
    uint256 _requesterBondedBalance = _accountingExtension.bondedAmountOf(requester, usdc, _requestId);
    uint256 _proposerBondedBalance = _accountingExtension.bondedAmountOf(proposer, usdc, _requestId);

    uint256 _requesterVirtualBalance = _accountingExtension.balanceOf(requester, usdc);
    uint256 _proposerVirtualBalance = _accountingExtension.balanceOf(proposer, usdc);

    assertEq(_requesterBondedBalance, 0);
    assertEq(_proposerBondedBalance, 0);

    assertEq(_requesterVirtualBalance, 0);
    assertEq(_proposerVirtualBalance, _expectedBondSize + _expectedReward);
  }
}
