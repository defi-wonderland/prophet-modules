// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/contracts/IOracle.sol';
import {IModule} from '@defi-wonderland/prophet-core-contracts/contracts/IModule.sol';

import {
  PrivateERC20ResolutionModule,
  IPrivateERC20ResolutionModule
} from '../../../../contracts/modules/resolution/PrivateERC20ResolutionModule.sol';
import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';
import {Helpers} from '../../../utils/Helpers.sol';

contract ForTest_PrivateERC20ResolutionModule is PrivateERC20ResolutionModule {
  constructor(IOracle _oracle) PrivateERC20ResolutionModule(_oracle) {}

  function forTest_setRequestData(bytes32 _requestId, bytes memory _data) public {
    requestData[_requestId] = _data;
  }

  function forTest_setEscalation(
    bytes32 _disputeId,
    PrivateERC20ResolutionModule.Escalation calldata __escalation
  ) public {
    escalations[_disputeId] = __escalation;
  }

  function forTest_setVoterData(
    bytes32 _disputeId,
    address _voter,
    IPrivateERC20ResolutionModule.VoterData memory _data
  ) public {
    _votersData[_disputeId][_voter] = _data;
  }

  function forTest_getVoterData(
    bytes32 _disputeId,
    address _voter
  ) public view returns (IPrivateERC20ResolutionModule.VoterData memory _data) {
    _data = _votersData[_disputeId][_voter];
  }
}

contract PrivateERC20ResolutionModule_UnitTest is Test, Helpers {
  // The target contract
  ForTest_PrivateERC20ResolutionModule public module;

  // A mock oracle
  IOracle public oracle;

  // A mock accounting extension
  IAccountingExtension public accounting;

  // A mock token
  IERC20 public token;

  // Mock EOA proposer
  address public proposer;

  // Mock EOA disputer
  address public disputer;

  // Mocking module events
  event CommittingPhaseStarted(uint256 _startTime, bytes32 _disputeId);
  event VoteCommitted(address _voter, bytes32 _disputeId, bytes32 _commitment);
  event VoteRevealed(address _voter, bytes32 _disputeId, uint256 _numberOfVotes);
  event DisputeResolved(bytes32 indexed _requestId, bytes32 indexed _disputeId, IOracle.DisputeStatus _status);

  /**
   * @notice Deploy the target and mock oracle+accounting extension
   */
  function setUp() public {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    accounting = IAccountingExtension(makeAddr('AccountingExtension'));
    vm.etch(address(accounting), hex'069420');

    token = IERC20(makeAddr('ERC20'));
    vm.etch(address(token), hex'069420');

    proposer = makeAddr('proposer');
    disputer = makeAddr('disputer');

    module = new ForTest_PrivateERC20ResolutionModule(oracle);
  }

  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleName() public {
    assertEq(module.moduleName(), 'PrivateERC20ResolutionModule');
  }

  /**
   * @notice Test that the startResolution is correctly called and the committing phase is started
   */
  function test_startResolution(bytes32 _disputeId) public {
    module.forTest_setEscalation(_disputeId, IPrivateERC20ResolutionModule.Escalation({startTime: 0, totalVotes: 0}));

    // Check: does revert if called by address != oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);
    module.startResolution(_disputeId);

    // Check: emits CommittingPhaseStarted event?
    vm.expectEmit(true, true, true, true);
    emit CommittingPhaseStarted(block.timestamp, _disputeId);

    vm.prank(address(oracle));
    module.startResolution(_disputeId);

    (uint256 _startTime,) = module.escalations(_disputeId);

    // Check: startTime is set to block.timestamp?
    assertEq(_startTime, block.timestamp);
  }

  /**
   * @notice Test that a user can store a vote commitment for a dispute
   */
  function test_commitVote(
    bytes32 _requestId,
    bytes32 _disputeId,
    uint256 _amountOfVotes,
    bytes32 _salt,
    address _voter
  ) public {
    // Mock the dispute
    IOracle.Dispute memory _mockDispute = _getMockDispute(_requestId, disputer, proposer);

    // Store mock escalation data with startTime 100_000
    module.forTest_setEscalation(
      _disputeId,
      IPrivateERC20ResolutionModule.Escalation({
        startTime: 100_000,
        totalVotes: 0 // Initial amount of votes
      })
    );

    // Store mock request data with 40_000 committing time window
    uint256 _minVotesForQuorum = 1;
    uint256 _committingTimeWindow = 40_000;
    uint256 _revealingTimewindow = 40_000;

    module.forTest_setRequestData(
      _requestId,
      abi.encode(address(accounting), token, _minVotesForQuorum, _committingTimeWindow, _revealingTimewindow)
    );

    // Mock the oracle response for looking up a dispute
    vm.mockCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));

    // Set timestamp for valid committingTimeWindow
    vm.warp(123_456);

    // Compute commitment
    vm.startPrank(_voter);
    bytes32 _commitment = module.computeCommitment(_disputeId, _amountOfVotes, _salt);

    // Check: is event emitted?
    vm.expectEmit(true, true, true, true);
    emit VoteCommitted(_voter, _disputeId, _commitment);

    // Revert if no commitment is given
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_EmptyCommitment.selector);
    module.commitVote(_requestId, _disputeId, bytes32(''));

    // Compute and store commitment
    module.commitVote(_requestId, _disputeId, _commitment);

    // Check: reverts if empty commitment is given?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_EmptyCommitment.selector);
    module.commitVote(_requestId, _disputeId, bytes32(''));

    // Check: commitment is stored?
    IPrivateERC20ResolutionModule.VoterData memory _voterData = module.forTest_getVoterData(_disputeId, _voter);
    assertEq(_voterData.commitment, _commitment);

    bytes32 _newCommitment = module.computeCommitment(_disputeId, uint256(_salt), bytes32(_amountOfVotes));
    module.commitVote(_requestId, _disputeId, _newCommitment);
    vm.stopPrank();

    // Check: does update with new commitment?
    IPrivateERC20ResolutionModule.VoterData memory _newVoterData = module.forTest_getVoterData(_disputeId, _voter);
    assertEq(_newVoterData.commitment, _newCommitment);
  }

  /**
   * @notice Test that `commitVote` reverts if there is no dispute with the given`_disputeId`
   */
  function test_revertCommitVote_NonExistentDispute(bytes32 _requestId, bytes32 _disputeId, bytes32 _commitment) public {
    IOracle.Dispute memory _mockDispute = IOracle.Dispute({
      disputer: address(0),
      responseId: bytes32(0),
      proposer: address(0),
      requestId: bytes32(0),
      status: IOracle.DisputeStatus.None,
      createdAt: 0
    });

    // Mock the oracle response for looking up a dispute
    vm.mockCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));

    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_NonExistentDispute.selector);
    module.commitVote(_requestId, _disputeId, _commitment);
  }

  /**
   * @notice Test that `commitVote` reverts if called with `_disputeId` of an already resolved dispute.
   */
  function test_revertCommitVote_AlreadyResolved(bytes32 _requestId, bytes32 _disputeId, bytes32 _commitment) public {
    // Mock dispute already resolved => DisputeStatus.Lost
    IOracle.Dispute memory _mockDispute = IOracle.Dispute({
      disputer: disputer,
      responseId: bytes32('response'),
      proposer: proposer,
      requestId: _requestId,
      status: IOracle.DisputeStatus.Lost,
      createdAt: block.timestamp
    });

    // Mock the oracle response for looking up a dispute
    vm.mockCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));

    // Check: reverts if dispute is already resolved?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_AlreadyResolved.selector);
    module.commitVote(_requestId, _disputeId, _commitment);
  }

  /**
   * @notice Test that `commitVote` reverts if called with `_disputeId` of a non-escalated dispute.
   */
  function test_revertCommitVote_NotEscalated(bytes32 _requestId, bytes32 _disputeId, bytes32 _commitment) public {
    // Mock the oracle response for looking up a dispute
    IOracle.Dispute memory _mockDispute = _getMockDispute(_requestId, disputer, proposer);
    vm.mockCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));

    // Check: reverts if dispute is not escalated? == no escalation data
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_DisputeNotEscalated.selector);
    module.commitVote(_requestId, _disputeId, _commitment);
  }

  /**
   * @notice Test that `commitVote` reverts if called outside of the committing time window.
   */
  function test_revertCommitVote_CommittingPhaseOver(
    bytes32 _requestId,
    bytes32 _disputeId,
    bytes32 _commitment
  ) public {
    // Mock the oracle response for looking up a dispute
    IOracle.Dispute memory _mockDispute = _getMockDispute(_requestId, disputer, proposer);
    vm.mockCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));

    module.forTest_setEscalation(
      _disputeId,
      IPrivateERC20ResolutionModule.Escalation({
        startTime: 100_000,
        totalVotes: 0 // Initial amount of votes
      })
    );

    uint256 _minVotesForQuorum = 1;
    uint256 _committingTimeWindow = 40_000;
    uint256 _revealingTimewindow = 40_000;

    module.forTest_setRequestData(
      _requestId,
      abi.encode(address(accounting), token, _minVotesForQuorum, _committingTimeWindow, _revealingTimewindow)
    );

    // Warp to invalid timestamp for commitment
    vm.warp(150_000);

    // Check: reverts if committing phase is over?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_CommittingPhaseOver.selector);
    module.commitVote(_requestId, _disputeId, _commitment);
  }

  /**
   * @notice Test revealing votes with proper timestamp, dispute status and commitment data.
   */
  function test_revealVote(
    bytes32 _requestId,
    bytes32 _disputeId,
    uint256 _amountOfVotes,
    bytes32 _salt,
    address _voter
  ) public {
    // Store mock escalation data with startTime 100_000
    module.forTest_setEscalation(
      _disputeId,
      IPrivateERC20ResolutionModule.Escalation({
        startTime: 100_000,
        totalVotes: 0 // Initial amount of votes
      })
    );

    // Store mock request data with 40_000 committing time window
    module.forTest_setRequestData(
      _requestId, abi.encode(address(accounting), token, uint256(1), uint256(40_000), uint256(40_000))
    );

    // Store commitment
    vm.prank(_voter);
    bytes32 _commitment = module.computeCommitment(_disputeId, _amountOfVotes, _salt);
    module.forTest_setVoterData(
      _disputeId, _voter, IPrivateERC20ResolutionModule.VoterData({numOfVotes: 0, commitment: _commitment})
    );

    // Mock token transfer (user must have approved token spending)
    vm.mockCall(
      address(token), abi.encodeCall(IERC20.transferFrom, (_voter, address(module), _amountOfVotes)), abi.encode()
    );
    vm.expectCall(address(token), abi.encodeCall(IERC20.transferFrom, (_voter, address(module), _amountOfVotes)));

    // Warp to revealing phase
    vm.warp(150_000);

    // Check: is event emmited?
    vm.expectEmit(true, true, true, true);
    emit VoteRevealed(_voter, _disputeId, _amountOfVotes);

    vm.prank(_voter);
    module.revealVote(_requestId, _disputeId, _amountOfVotes, _salt);

    (, uint256 _totalVotes) = module.escalations(_disputeId);
    // Check: totalVotes is updated?
    assertEq(_totalVotes, _amountOfVotes);

    // Check: voter data is updated?
    IPrivateERC20ResolutionModule.VoterData memory _voterData = module.forTest_getVoterData(_disputeId, _voter);
    assertEq(_voterData.numOfVotes, _amountOfVotes);
  }

  /**
   * @notice Test that `revealVote` reverts if called with `_disputeId` of a non-escalated dispute.
   */
  function test_revertRevealVote_NotEscalated(
    bytes32 _requestId,
    bytes32 _disputeId,
    uint256 _numberOfVotes,
    bytes32 _salt
  ) public {
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_DisputeNotEscalated.selector);
    module.revealVote(_requestId, _disputeId, _numberOfVotes, _salt);
  }

  /**
   * @notice Test that `revealVote` reverts if called outside the revealing time window.
   */
  function test_revertRevealVote_InvalidPhase(
    bytes32 _requestId,
    bytes32 _disputeId,
    uint256 _numberOfVotes,
    bytes32 _salt,
    uint256 _timestamp
  ) public {
    vm.assume(_timestamp >= 100_000 && (_timestamp <= 140_000 || _timestamp > 180_000));

    module.forTest_setEscalation(
      _disputeId,
      IPrivateERC20ResolutionModule.Escalation({
        startTime: 100_000,
        totalVotes: 0 // Initial amount of votes
      })
    );

    // Store request data
    uint256 _minVotesForQuorum = 1;
    uint256 _committingTimeWindow = 40_000;
    uint256 _revealingTimewindow = 40_000;

    module.forTest_setRequestData(
      _requestId,
      abi.encode(address(accounting), token, _minVotesForQuorum, _committingTimeWindow, _revealingTimewindow)
    );

    // Jump to timestamp
    vm.warp(_timestamp);

    if (_timestamp <= 140_000) {
      // Check: reverts if trying to reveal during committing phase?
      vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_OnGoingCommittingPhase.selector);
      module.revealVote(_requestId, _disputeId, _numberOfVotes, _salt);
    } else {
      // Check: reverts if trying to reveal after revealing phase?
      vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_RevealingPhaseOver.selector);
      module.revealVote(_requestId, _disputeId, _numberOfVotes, _salt);
    }
  }

  /**
   * @notice Test that `revealVote` reverts if called with revealing parameters (`_disputeId`, `_numberOfVotes`, `_salt`)
   * that do not compute to the stored commitment.
   */
  function test_revertRevealVote_FalseCommitment(
    bytes32 _requestId,
    bytes32 _disputeId,
    uint256 _amountOfVotes,
    uint256 _wrongAmountOfVotes,
    bytes32 _salt,
    bytes32 _wrongSalt,
    address _voter,
    address _wrongVoter
  ) public {
    vm.assume(_amountOfVotes != _wrongAmountOfVotes);
    vm.assume(_salt != _wrongSalt);
    vm.assume(_voter != _wrongVoter);

    module.forTest_setEscalation(
      _disputeId,
      IPrivateERC20ResolutionModule.Escalation({
        startTime: 100_000,
        totalVotes: 0 // Initial amount of votes
      })
    );

    // Store request data
    uint256 _minVotesForQuorum = 1;
    uint256 _committingTimeWindow = 40_000;
    uint256 _revealingTimewindow = 40_000;

    module.forTest_setRequestData(
      _requestId,
      abi.encode(address(accounting), token, _minVotesForQuorum, _committingTimeWindow, _revealingTimewindow)
    );
    vm.warp(150_000);

    vm.startPrank(_voter);
    bytes32 _commitment = module.computeCommitment(_disputeId, _amountOfVotes, _salt);
    module.forTest_setVoterData(
      _disputeId, _voter, IPrivateERC20ResolutionModule.VoterData({numOfVotes: 0, commitment: _commitment})
    );

    // Check: reverts if commitment is not valid? (wrong salt)
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_WrongRevealData.selector);
    module.revealVote(_requestId, _disputeId, _amountOfVotes, _wrongSalt);

    // Check: reverts if commitment is not valid? (wrong amount of votes)
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_WrongRevealData.selector);
    module.revealVote(_requestId, _disputeId, _wrongAmountOfVotes, _salt);
    vm.stopPrank();

    // Check: reverts if commitment is not valid? (wrong voter)
    vm.prank(_wrongVoter);
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_WrongRevealData.selector);
    module.revealVote(_requestId, _disputeId, _amountOfVotes, _salt);
  }

  /**
   * @notice Test that a dispute is resolved, the tokens are transferred back to the voters and the dispute status updated.
   */
  function test_resolveDispute(bytes32 _requestId, bytes32 _disputeId, uint16 _minVotesForQuorum) public {
    // Store mock dispute and mock calls
    IOracle.Dispute memory _mockDispute = _getMockDispute(_requestId, disputer, proposer);

    vm.mockCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));

    // Store request data
    uint256 _committingTimeWindow = 40_000;
    uint256 _revealingTimewindow = 40_000;

    module.forTest_setRequestData(
      _requestId,
      abi.encode(address(accounting), token, _minVotesForQuorum, _committingTimeWindow, _revealingTimewindow)
    );

    // Store escalation data with starttime 100_000 and votes 0
    module.forTest_setEscalation(
      _disputeId, IPrivateERC20ResolutionModule.Escalation({startTime: 100_000, totalVotes: 0})
    );

    uint256 _votersAmount = 5;

    // Make 5 addresses cast 100 votes each
    uint256 _totalVotesCast = _populateVoters(_requestId, _disputeId, _votersAmount, 100);

    // Warp to resolving phase
    vm.warp(190_000);

    // Mock and expect token transfers (should happen always)
    for (uint256 _i = 1; _i <= _votersAmount;) {
      vm.mockCall(address(token), abi.encodeCall(IERC20.transfer, (vm.addr(_i), 100)), abi.encode());
      vm.expectCall(address(token), abi.encodeCall(IERC20.transfer, (vm.addr(_i), 100)));
      unchecked {
        ++_i;
      }
    }

    // If quorum reached, check for dispute status update and event emission
    IOracle.DisputeStatus _newStatus =
      _totalVotesCast >= _minVotesForQuorum ? IOracle.DisputeStatus.Won : IOracle.DisputeStatus.Lost;
    vm.mockCall(address(oracle), abi.encodeCall(IOracle.updateDisputeStatus, (_disputeId, _newStatus)), abi.encode());
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.updateDisputeStatus, (_disputeId, _newStatus)));
    vm.expectEmit(true, true, true, true);
    emit DisputeResolved(_requestId, _disputeId, _newStatus);

    // Check: does revert if called by address != oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);
    module.resolveDispute(_disputeId);

    vm.prank(address(oracle));
    module.resolveDispute(_disputeId);
  }

  /**
   * @notice Test that `resolveDispute` reverts if called during committing or reavealing time window.
   */
  function test_revertResolveDispute_WrongPhase(bytes32 _requestId, bytes32 _disputeId, uint256 _timestamp) public {
    _timestamp = bound(_timestamp, 1, 1_000_000);

    // Store mock dispute and mock calls
    IOracle.Dispute memory _mockDispute = _getMockDispute(_requestId, disputer, proposer);

    vm.mockCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)), abi.encode(_mockDispute));
    vm.expectCall(address(oracle), abi.encodeCall(IOracle.getDispute, (_disputeId)));

    module.forTest_setEscalation(
      _disputeId,
      IPrivateERC20ResolutionModule.Escalation({
        startTime: 1,
        totalVotes: 0 // Initial amount of votes
      })
    );

    // Store request data
    uint256 _minVotesForQuorum = 1;
    uint256 _committingTimeWindow = 500_000;
    uint256 _revealingTimeWindow = 1_000_000;

    module.forTest_setRequestData(
      _requestId,
      abi.encode(address(accounting), token, _minVotesForQuorum, _committingTimeWindow, _revealingTimeWindow)
    );

    // Jump to timestamp
    vm.warp(_timestamp);

    if (_timestamp <= 500_000) {
      // Check: reverts if trying to resolve during committing phase?
      vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_OnGoingCommittingPhase.selector);
      vm.prank(address(oracle));
      module.resolveDispute(_disputeId);
    } else {
      // Check: reverts if trying to resolve during revealing phase?
      vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_OnGoingRevealingPhase.selector);
      vm.prank(address(oracle));
      module.resolveDispute(_disputeId);
    }
  }

  /**
   * @dev Helper function to store commitments and reveal votes.
   */
  function _populateVoters(
    bytes32 _requestId,
    bytes32 _disputeId,
    uint256 _amountOfVoters,
    uint256 _amountOfVotes
  ) internal returns (uint256 _totalVotesCast) {
    for (uint256 _i = 1; _i <= _amountOfVoters;) {
      vm.warp(120_000);
      vm.startPrank(vm.addr(_i));
      bytes32 _commitment = module.computeCommitment(_disputeId, _amountOfVotes, bytes32(_i)); // index as salt
      module.commitVote(_requestId, _disputeId, _commitment);
      vm.warp(140_001);
      vm.mockCall(
        address(token),
        abi.encodeCall(IERC20.transferFrom, (vm.addr(_i), address(module), _amountOfVotes)),
        abi.encode()
      );
      module.revealVote(_requestId, _disputeId, _amountOfVotes, bytes32(_i));
      vm.stopPrank();
      _totalVotesCast += _amountOfVotes;
      unchecked {
        ++_i;
      }
    }
  }
}
