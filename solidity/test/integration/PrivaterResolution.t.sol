// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {
  IPrivateERC20ResolutionModule,
  PrivateERC20ResolutionModule
} from '../../contracts/modules/resolution/PrivateERC20ResolutionModule.sol';
import './IntegrationBase.sol';

contract Integration_PrivateResolution is IntegrationBase {
  PrivateERC20ResolutionModule public privateERC20ResolutionModule;

  IERC20 internal _votingToken;
  uint256 internal _minimumQuorum = 1000;
  uint256 internal _committingTimeWindow = 1 days;
  uint256 internal _revealingTimeWindow = 1 days;

  address internal _voterA = makeAddr('voter-a');
  address internal _voterB = makeAddr('voter-b');
  bytes32 internal _disputeId;

  bytes32 internal _goodSalt = keccak256('salty');

  function setUp() public override {
    super.setUp();

    vm.prank(governance);
    privateERC20ResolutionModule = new PrivateERC20ResolutionModule(oracle);

    _votingToken = IERC20(address(weth));

    mockRequest.resolutionModule = address(privateERC20ResolutionModule);
    mockRequest.resolutionModuleData = abi.encode(
      IPrivateERC20ResolutionModule.RequestParameters({
        accountingExtension: _accountingExtension,
        votingToken: _votingToken,
        minVotesForQuorum: _minimumQuorum,
        committingTimeWindow: _committingTimeWindow,
        revealingTimeWindow: _revealingTimeWindow
      })
    );

    _deposit(_accountingExtension, requester, usdc, _expectedReward);
    _deposit(_accountingExtension, proposer, usdc, _expectedBondSize);
    _deposit(_accountingExtension, disputer, usdc, _expectedBondSize);

    _setupEscalatedDispute();
  }

  function test_resolve_noVotes() public {
    // expect call to update dispute' status as lost
    vm.expectCall(
      address(oracle),
      abi.encodeCall(IOracle.updateDisputeStatus, (mockRequest, mockResponse, mockDispute, IOracle.DisputeStatus.Lost))
    );

    (uint256 _startTime, uint256 _totalVotes) = privateERC20ResolutionModule.escalations(_disputeId);
    assertEq(_startTime, block.timestamp);
    assertEq(_totalVotes, 0);

    vm.warp(block.timestamp + _committingTimeWindow + _revealingTimeWindow + 1);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);

    (_startTime,) = privateERC20ResolutionModule.escalations(_disputeId);
    assertEq(_totalVotes, 0);
  }

  function test_resolve_enoughVotes() public {
    // we have enough votes to reach the quorum
    uint256 _votes = _minimumQuorum + 1;

    // expect call to update dispute' status as won
    vm.expectCall(
      address(oracle),
      abi.encodeCall(IOracle.updateDisputeStatus, (mockRequest, mockResponse, mockDispute, IOracle.DisputeStatus.Won))
    );

    // expect call to transfer tokens from voter to module
    vm.expectCall(
      address(_votingToken),
      abi.encodeCall(IERC20.transferFrom, (_voterA, address(privateERC20ResolutionModule), _votes))
    );

    // expect call to transfer tokens to voter
    vm.expectCall(address(_votingToken), abi.encodeCall(IERC20.transfer, (_voterA, _votes)));

    // warp into the commiting window
    vm.warp(block.timestamp);

    deal(address(_votingToken), _voterA, _votes);
    vm.startPrank(_voterA);
    _votingToken.approve(address(privateERC20ResolutionModule), _votes);
    bytes32 _commitment = privateERC20ResolutionModule.computeCommitment(_disputeId, _votes, _goodSalt);
    privateERC20ResolutionModule.commitVote(mockRequest, mockDispute, _commitment);

    // warp past the commiting window
    vm.warp(block.timestamp + _committingTimeWindow + 1);
    privateERC20ResolutionModule.revealVote(mockRequest, mockDispute, _votes, _goodSalt);

    vm.stopPrank();

    // warp past the revealing window
    vm.warp(block.timestamp + _revealingTimeWindow);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);
  }

  function test_resolve_notEnoughVotes() public {
    uint256 _votes = _minimumQuorum - 1;

    vm.expectCall(
      address(oracle),
      abi.encodeCall(IOracle.updateDisputeStatus, (mockRequest, mockResponse, mockDispute, IOracle.DisputeStatus.Lost))
    );

    vm.expectCall(
      address(_votingToken),
      abi.encodeCall(IERC20.transferFrom, (_voterA, address(privateERC20ResolutionModule), _votes))
    );

    vm.expectCall(address(_votingToken), abi.encodeCall(IERC20.transfer, (_voterA, _votes)));

    // warp into the commiting window
    vm.warp(block.timestamp);

    deal(address(_votingToken), _voterA, _votes);

    vm.startPrank(_voterA);

    _votingToken.approve(address(privateERC20ResolutionModule), _votes);
    bytes32 _commitment = privateERC20ResolutionModule.computeCommitment(_disputeId, _votes, _goodSalt);
    privateERC20ResolutionModule.commitVote(mockRequest, mockDispute, _commitment);

    vm.warp(block.timestamp + _committingTimeWindow + 1);
    privateERC20ResolutionModule.revealVote(mockRequest, mockDispute, _votes, _goodSalt);

    vm.stopPrank();

    vm.warp(block.timestamp + _revealingTimeWindow);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);
  }

  function _setupEscalatedDispute() internal {
    _resetMockIds();

    _createRequest();
    _proposeResponse();
    _disputeId = _disputeResponse();

    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);
  }
}
