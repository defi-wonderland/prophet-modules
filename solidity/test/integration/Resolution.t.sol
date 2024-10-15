// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {
  ERC20ResolutionModule, IERC20ResolutionModule
} from '../../contracts/modules/resolution/ERC20ResolutionModule.sol';
import './IntegrationBase.sol';

contract Integration_Resolution is IntegrationBase {
  ERC20ResolutionModule internal _erc20ResolutionModule;

  IERC20 internal _votingToken;
  uint256 internal _minimumQuorum = 1000;
  uint256 internal _timeUntilDeadline = 1 days;

  address internal _voterA = makeAddr('voter-a');
  address internal _voterB = makeAddr('voter-b');
  bytes32 internal _disputeId;

  function setUp() public override {
    super.setUp();

    vm.prank(governance);
    _erc20ResolutionModule = new ERC20ResolutionModule(oracle);

    _votingToken = IERC20(address(weth));

    mockRequest.resolutionModule = address(_erc20ResolutionModule);
    mockRequest.resolutionModuleData = abi.encode(
      IERC20ResolutionModule.RequestParameters({
        accountingExtension: _accountingExtension,
        votingToken: _votingToken,
        minVotesForQuorum: _minimumQuorum,
        timeUntilDeadline: _timeUntilDeadline
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

    (uint256 _startTime, uint256 _totalVotes) = _erc20ResolutionModule.escalations(_disputeId);
    assertEq(_startTime, block.timestamp);
    assertEq(_totalVotes, 0);

    vm.warp(block.timestamp + _timeUntilDeadline);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);

    (_startTime,) = _erc20ResolutionModule.escalations(_disputeId);
    assertEq(_totalVotes, 0);
  }

  function test_resolve_enoughVotes() public {
    uint256 _votes = _minimumQuorum + 1;

    // expect call to update dispute' status as won
    vm.expectCall(
      address(oracle),
      abi.encodeCall(IOracle.updateDisputeStatus, (mockRequest, mockResponse, mockDispute, IOracle.DisputeStatus.Won))
    );

    // expect call to transfer tokens from voter to module
    vm.expectCall(
      address(_votingToken), abi.encodeCall(IERC20.transferFrom, (_voterA, address(_erc20ResolutionModule), _votes))
    );

    // expect call to transfer tokens to voter
    vm.expectCall(address(_votingToken), abi.encodeCall(IERC20.transfer, (_voterA, _votes)));

    deal(address(_votingToken), _voterA, _votes);
    vm.startPrank(_voterA);
    _votingToken.approve(address(_erc20ResolutionModule), _votes);
    _erc20ResolutionModule.castVote(mockRequest, mockDispute, _votes);
    vm.stopPrank();

    vm.warp(block.timestamp + _timeUntilDeadline);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);

    vm.prank(_voterA);
    _erc20ResolutionModule.claimVote(mockRequest, mockDispute);
  }

  function test_resolve_notEnoughVotes() public {
    uint256 _votes = _minimumQuorum - 1;

    vm.expectCall(
      address(oracle),
      abi.encodeCall(IOracle.updateDisputeStatus, (mockRequest, mockResponse, mockDispute, IOracle.DisputeStatus.Lost))
    );

    vm.expectCall(
      address(_votingToken), abi.encodeCall(IERC20.transferFrom, (_voterA, address(_erc20ResolutionModule), _votes))
    );

    vm.expectCall(address(_votingToken), abi.encodeCall(IERC20.transfer, (_voterA, _votes)));

    deal(address(_votingToken), _voterA, _votes);
    vm.startPrank(_voterA);
    _votingToken.approve(address(_erc20ResolutionModule), _votes);
    _erc20ResolutionModule.castVote(mockRequest, mockDispute, _votes);
    vm.stopPrank();

    vm.warp(block.timestamp + _timeUntilDeadline);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);

    vm.prank(_voterA);
    _erc20ResolutionModule.claimVote(mockRequest, mockDispute);
  }

  function _setupEscalatedDispute() internal {
    _resetMockIds();

    _createRequest();
    _proposeResponse();
    _disputeId = _disputeResponse();

    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);
  }
}
