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

    _setupDispute();
  }

  function test_resolve_noVotes() public {
    // expect call to startResolution
    vm.expectCall(
      address(privateERC20ResolutionModule),
      abi.encodeCall(
        IPrivateERC20ResolutionModule.startResolution, (_disputeId, mockRequest, mockResponse, mockDispute)
      )
    );

    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

    // expect call to update dispute' status as lost
    vm.expectCall(
      address(oracle),
      abi.encodeCall(IOracle.updateDisputeStatus, (mockRequest, mockResponse, mockDispute, IOracle.DisputeStatus.Lost))
    );

    // expect call to resolveDispute
    vm.expectCall(
      address(privateERC20ResolutionModule),
      abi.encodeCall(IPrivateERC20ResolutionModule.resolveDispute, (_disputeId, mockRequest, mockResponse, mockDispute))
    );

    (uint256 _startTime, uint256 _totalVotes) = privateERC20ResolutionModule.escalations(_disputeId);
    assertEq(_startTime, block.timestamp);
    assertEq(_totalVotes, 0);

    // expect revert when try to resolve before the committing phase is over
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_OnGoingCommittingPhase.selector);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);

    // warp past the committing phase
    vm.warp(block.timestamp + _committingTimeWindow + 1);
    // expect revert when try to resolve before the revealing phase is over
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_OnGoingRevealingPhase.selector);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);

    // warp past the revealing phase
    vm.warp(block.timestamp + _revealingTimeWindow);

    // successfully resolve the dispute
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);

    (_startTime, _totalVotes) = privateERC20ResolutionModule.escalations(_disputeId);
    assertEq(_totalVotes, 0);
  }

  function test_resolve_enoughVotes() public {
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

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
    vm.warp(block.timestamp + 1);

    deal(address(_votingToken), _voterA, _votes);
    vm.startPrank(_voterA);
    _votingToken.approve(address(privateERC20ResolutionModule), _votes);
    bytes32 _commitment = privateERC20ResolutionModule.computeCommitment(_disputeId, _votes, _goodSalt);
    privateERC20ResolutionModule.commitVote(mockRequest, mockDispute, _commitment);

    // warp past the commiting window
    vm.warp(block.timestamp + _committingTimeWindow + 1);

    // assert has enough voting tokens
    assertEq(_votingToken.balanceOf(_voterA), _votes);
    privateERC20ResolutionModule.revealVote(mockRequest, mockDispute, _votes, _goodSalt);
    // assert voting tokens were transfered
    assertEq(_votingToken.balanceOf(_voterA), 0);
    assertEq(_votingToken.balanceOf(address(privateERC20ResolutionModule)), _votes);

    vm.stopPrank();

    // warp past the revealing window
    vm.warp(block.timestamp + _revealingTimeWindow);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);

    // assert voting tokens were transfered back to the voter.
    assertEq(_votingToken.balanceOf(_voterA), _votes);
    assertEq(_votingToken.balanceOf(address(privateERC20ResolutionModule)), 0);
  }

  function test_resolve_notEnoughVotes() public {
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

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
    vm.warp(block.timestamp + 1);

    deal(address(_votingToken), _voterA, _votes);

    vm.startPrank(_voterA);

    _votingToken.approve(address(privateERC20ResolutionModule), _votes);
    bytes32 _commitment = privateERC20ResolutionModule.computeCommitment(_disputeId, _votes, _goodSalt);
    privateERC20ResolutionModule.commitVote(mockRequest, mockDispute, _commitment);

    // warp into the committing phase
    vm.warp(block.timestamp + _committingTimeWindow);
    privateERC20ResolutionModule.revealVote(mockRequest, mockDispute, _votes, _goodSalt);

    vm.stopPrank();

    vm.warp(block.timestamp + _revealingTimeWindow);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);
  }

  function test_resolve_noEscalation() public {
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_AlreadyResolved.selector);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);
  }

  function test_zeroVotes() public {
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

    uint256 _votes = 0;

    // expect call to transfer `0` tokens to voterB
    vm.expectCall(address(_votingToken), abi.encodeCall(IERC20.transfer, (_voterA, 0)));

    vm.startPrank(_voterA);
    bytes32 _commitment = privateERC20ResolutionModule.computeCommitment(_disputeId, _votes, _goodSalt);
    privateERC20ResolutionModule.commitVote(mockRequest, mockDispute, _commitment);
    vm.stopPrank();

    // warp past the commiting phase
    vm.warp(block.timestamp + _committingTimeWindow + 1);

    // expert to revert because the sender is not correct
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_WrongRevealData.selector);
    vm.prank(_voterB);
    privateERC20ResolutionModule.revealVote(mockRequest, mockDispute, _votes, _goodSalt);

    vm.prank(_voterA);
    privateERC20ResolutionModule.revealVote(mockRequest, mockDispute, _votes, _goodSalt);

    vm.warp(block.timestamp + _revealingTimeWindow + 1);
    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);

    assertEq(_votingToken.balanceOf(_voterA), 0);
    assertEq(_votingToken.balanceOf(address(privateERC20ResolutionModule)), 0);
  }

  function test_commit() public {
    uint256 _votes = 0;

    vm.startPrank(_voterA);
    bytes32 _commitment = privateERC20ResolutionModule.computeCommitment(_disputeId, _votes, _goodSalt);

    // expect revert when trying to commit a vote into an already resolved dispute
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_AlreadyResolved.selector);
    privateERC20ResolutionModule.commitVote(mockRequest, mockDispute, _commitment);

    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

    // expect revert when trying to commit a vote with an empty commitment
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_EmptyCommitment.selector);
    privateERC20ResolutionModule.commitVote(mockRequest, mockDispute, bytes32(''));

    // successfully commit a vote
    privateERC20ResolutionModule.commitVote(mockRequest, mockDispute, _commitment);

    // warp past the committing phase
    vm.warp(block.timestamp + _committingTimeWindow);

    // expect revert when trying to commit after the committing phase is over
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_CommittingPhaseOver.selector);
    privateERC20ResolutionModule.commitVote(mockRequest, mockDispute, _commitment);

    vm.stopPrank();
  }

  function test_reveal() public {
    uint256 _votes = 0;

    vm.startPrank(_voterA);

    // expect revert when reveal a commit into a not escalated dispute
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_DisputeNotEscalated.selector);
    privateERC20ResolutionModule.revealVote(mockRequest, mockDispute, _votes, _goodSalt);

    bytes32 _commitment = privateERC20ResolutionModule.computeCommitment(_disputeId, _votes, _goodSalt);

    // escalate and commit a vote using `_goodSalt`
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);
    privateERC20ResolutionModule.commitVote(mockRequest, mockDispute, _commitment);

    // expect revert when trying to reveal vote during committing phase
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_OnGoingCommittingPhase.selector);
    privateERC20ResolutionModule.revealVote(mockRequest, mockDispute, _votes, _goodSalt);

    // warp past the committing phase
    vm.warp(block.timestamp + _committingTimeWindow + 1);

    // expect revert when trying to reveal a vote using the incorrect salt
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_WrongRevealData.selector);
    privateERC20ResolutionModule.revealVote(mockRequest, mockDispute, _votes, bytes32('bad-salt'));

    // succesfully reveal a vote
    privateERC20ResolutionModule.revealVote(mockRequest, mockDispute, _votes, _goodSalt);

    // warp past the revealing phase
    vm.warp(block.timestamp + _revealingTimeWindow);

    // expect revert when trying to reveal a vote phase the revealing phase
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_RevealingPhaseOver.selector);
    privateERC20ResolutionModule.revealVote(mockRequest, mockDispute, _votes, _goodSalt);

    vm.stopPrank();
  }

  function test_multipleVoters() public {
    oracle.escalateDispute(mockRequest, mockResponse, mockDispute);

    uint256 _votes = 10;

    // expect call to transfer `0` tokens to voterB
    vm.expectCall(address(_votingToken), abi.encodeCall(IERC20.transfer, (_voterA, _votes)), 1);
    vm.expectCall(address(_votingToken), abi.encodeCall(IERC20.transfer, (_voterB, _votes)), 1);

    // voterA cast votes
    deal(address(_votingToken), _voterA, _votes);
    vm.startPrank(_voterA);
    _votingToken.approve(address(privateERC20ResolutionModule), _votes);
    privateERC20ResolutionModule.commitVote(
      mockRequest, mockDispute, privateERC20ResolutionModule.computeCommitment(_disputeId, _votes, _goodSalt)
    );
    vm.stopPrank();

    // voterB cast votes
    deal(address(_votingToken), _voterB, _votes);
    vm.startPrank(_voterB);
    _votingToken.approve(address(privateERC20ResolutionModule), _votes);
    privateERC20ResolutionModule.commitVote(
      mockRequest, mockDispute, privateERC20ResolutionModule.computeCommitment(_disputeId, _votes, _goodSalt)
    );
    vm.stopPrank();

    // warp past the voting phase
    vm.warp(block.timestamp + _committingTimeWindow + 1);

    vm.prank(_voterA);
    privateERC20ResolutionModule.revealVote(mockRequest, mockDispute, _votes, _goodSalt);

    // expect revert because the salt is not correct
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_WrongRevealData.selector);
    vm.prank(_voterB);
    privateERC20ResolutionModule.revealVote(mockRequest, mockDispute, _votes, bytes32('bad salt'));

    vm.prank(_voterB);
    privateERC20ResolutionModule.revealVote(mockRequest, mockDispute, _votes, _goodSalt);

    vm.stopPrank();

    vm.warp(block.timestamp + _revealingTimeWindow + 1);

    oracle.resolveDispute(mockRequest, mockResponse, mockDispute);

    // both voters get their votes back
    assertEq(_votingToken.balanceOf(_voterA), _votes);
    assertEq(_votingToken.balanceOf(_voterB), _votes);
  }

  function _setupDispute() internal {
    _resetMockIds();

    _createRequest();
    _proposeResponse();
    _disputeId = _disputeResponse();
  }
}
