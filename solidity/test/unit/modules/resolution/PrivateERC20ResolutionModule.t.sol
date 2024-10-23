// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IModule} from '@defi-wonderland/prophet-core/solidity/interfaces/IModule.sol';
import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';
import {IValidator} from '@defi-wonderland/prophet-core/solidity/interfaces/IValidator.sol';
import {ValidatorLib} from '@defi-wonderland/prophet-core/solidity/libraries/ValidatorLib.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {
  IPrivateERC20ResolutionModule,
  PrivateERC20ResolutionModule
} from '../../../../contracts/modules/resolution/PrivateERC20ResolutionModule.sol';
import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';

contract ForTest_PrivateERC20ResolutionModule is PrivateERC20ResolutionModule {
  constructor(IOracle _oracle) PrivateERC20ResolutionModule(_oracle) {}

  function forTest_setStartTime(bytes32 _disputeId, uint256 _startTime) public {
    escalations[_disputeId] = IPrivateERC20ResolutionModule.Escalation({
      startTime: _startTime,
      totalVotes: 0 // Initial amount of votes
    });
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

contract BaseTest is Test, Helpers {
  // The target contract
  ForTest_PrivateERC20ResolutionModule public module;
  // A mock oracle
  IOracle public oracle;
  // A mock token
  IERC20 public token;

  // Events
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

    token = IERC20(makeAddr('ERC20'));
    vm.etch(address(token), hex'069420');

    module = new ForTest_PrivateERC20ResolutionModule(oracle);
  }

  /**
   * @dev Helper function to store commitments and reveal votes.
   */
  function _populateVoters(
    IOracle.Request storage _request,
    IOracle.Dispute storage _dispute,
    uint256 _amountOfVoters,
    uint256 _amountOfVotes
  ) internal returns (uint256 _totalVotesCast) {
    bytes32 _disputeId = _getId(_dispute);

    for (uint256 _i = 1; _i <= _amountOfVoters;) {
      vm.warp(120_000);
      vm.startPrank(vm.addr(_i));

      bytes32 _commitment = module.computeCommitment(_disputeId, _amountOfVotes, bytes32(_i)); // index as salt

      _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));
      _mockAndExpect(
        address(oracle),
        abi.encodeCall(IOracle.disputeStatus, (_disputeId)),
        abi.encode(IOracle.DisputeStatus.Escalated)
      );
      module.commitVote(_request, _dispute, _commitment, _createAccessControl());

      vm.warp(140_001);

      vm.mockCall(
        address(token),
        abi.encodeCall(IERC20.transferFrom, (vm.addr(_i), address(module), _amountOfVotes)),
        abi.encode()
      );
      module.revealVote(_request, _dispute, _amountOfVotes, bytes32(_i), _createAccessControl());
      vm.stopPrank();
      _totalVotesCast += _amountOfVotes;
      unchecked {
        ++_i;
      }
    }
  }
}

contract PrivateERC20ResolutionModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleName() public view {
    assertEq(module.moduleName(), 'PrivateERC20ResolutionModule');
  }

  /**
   * @notice Test that the validateParameters function correctly checks the parameters
   */
  function test_validateParameters(IPrivateERC20ResolutionModule.RequestParameters calldata _params) public view {
    if (
      address(_params.accountingExtension) == address(0) || address(_params.votingToken) == address(0)
        || _params.minVotesForQuorum == 0 || _params.committingTimeWindow == 0 || _params.revealingTimeWindow == 0
    ) {
      assertFalse(module.validateParameters(abi.encode(_params)));
    } else {
      assertTrue(module.validateParameters(abi.encode(_params)));
    }
  }
}

contract PrivateERC20ResolutionModule_Unit_StartResolution is BaseTest {
  /**
   * @notice Test that the startResolution is correctly called and the committing phase is started
   */
  function test_startResolution(bytes32 _disputeId, uint256 _timestamp) public {
    module.forTest_setStartTime(_disputeId, 0);

    // Check: does revert if called by address != oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);
    module.startResolution(_disputeId, mockRequest, mockResponse, mockDispute);

    // Check: emits CommittingPhaseStarted event?
    vm.expectEmit(true, true, true, true);
    emit CommittingPhaseStarted(_timestamp, _disputeId);

    vm.warp(_timestamp);
    vm.prank(address(oracle));
    module.startResolution(_disputeId, mockRequest, mockResponse, mockDispute);

    (uint256 _startTime,) = module.escalations(_disputeId);

    // Check: startTime is set to _timestamp?
    assertEq(_startTime, _timestamp);
  }
}

contract PrivateERC20ResolutionModule_Unit_CommitVote is BaseTest {
  /**
   * @notice Test that a user can store a vote commitment for a dispute
   */
  function test_commitVote(uint256 _amountOfVotes, bytes32 _salt, address _voter) public {
    // Set mock request data
    mockRequest.resolutionModuleData = abi.encode(
      IPrivateERC20ResolutionModule.RequestParameters({
        accountingExtension: IAccountingExtension(makeAddr('AccountingExtension')),
        votingToken: token,
        minVotesForQuorum: 1,
        committingTimeWindow: 40_000,
        revealingTimeWindow: 40_000
      })
    );

    // Compute proper ids
    bytes32 _requestId = _getId(mockRequest);
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Store mock escalation data with startTime 100_000
    module.forTest_setStartTime(_disputeId, 100_000);

    // Set timestamp for valid committingTimeWindow
    vm.warp(123_456);

    // Compute commitment
    vm.startPrank(_voter);
    bytes32 _commitment = module.computeCommitment(_disputeId, _amountOfVotes, _salt);

    // Check: is event emitted?
    vm.expectEmit(true, true, true, true);
    emit VoteCommitted(_voter, _disputeId, _commitment);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));
    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    // Check: does it revert if no commitment is given?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_EmptyCommitment.selector);
    module.commitVote(mockRequest, mockDispute, bytes32(''), _createAccessControl());

    // Compute and store commitment
    module.commitVote(mockRequest, mockDispute, _commitment, _createAccessControl());

    // Check: reverts if empty commitment is given?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_EmptyCommitment.selector);
    module.commitVote(mockRequest, mockDispute, bytes32(''), _createAccessControl());

    // Check: is the commitment stored?
    IPrivateERC20ResolutionModule.VoterData memory _voterData = module.forTest_getVoterData(_disputeId, _voter);
    assertEq(_voterData.commitment, _commitment);

    bytes32 _newCommitment = module.computeCommitment(_disputeId, uint256(_salt), bytes32(_amountOfVotes));
    module.commitVote(mockRequest, mockDispute, _newCommitment, _createAccessControl());
    vm.stopPrank();

    // Check: is voters data updated with new commitment?
    IPrivateERC20ResolutionModule.VoterData memory _newVoterData = module.forTest_getVoterData(_disputeId, _voter);
    assertEq(_newVoterData.commitment, _newCommitment);
  }

  /**
   * @notice Test that `commitVote` reverts if the dispute body is invalid.
   */
  function test_revertIfInvalidDisputeBody(bytes32 _commitment) public {
    // Check: does it revert if the dispute body is invalid?
    mockDispute.requestId = bytes32(0);
    vm.expectRevert(ValidatorLib.ValidatorLib_InvalidDisputeBody.selector);
    module.commitVote(mockRequest, mockDispute, _commitment, _createAccessControl(address(this)));
  }

  /**
   * @notice Test that `commitVote` reverts if there is no dispute with the given`_disputeId`.
   */
  function test_revertIfNonExistentDispute(bytes32 _commitment) public {
    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(0));

    // Check: does it revert if no dispute exists?
    vm.expectRevert(IValidator.Validator_InvalidDispute.selector);
    module.commitVote(mockRequest, _dispute, _commitment, _createAccessControl(address(this)));
  }

  /**
   * @notice Test that `commitVote` reverts if called with `_disputeId` of an already active dispute.
   */
  function test_revertIfActive(bytes32 _commitment) public {
    // Computer proper IDs
    bytes32 _requestId = _getId(mockRequest);
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));
    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Active)
    );

    // Check: does it revert if the dispute is already resolved?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_AlreadyResolved.selector);
    module.commitVote(mockRequest, mockDispute, _commitment, _createAccessControl(address(this)));
  }

  /**
   * @notice Test that `commitVote` reverts if called with `_disputeId` of a dispute with no resolution.
   */
  function test_revertIfNoResolution(bytes32 _commitment) public {
    // Computer proper IDs
    bytes32 _requestId = _getId(mockRequest);
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));
    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle),
      abi.encodeCall(IOracle.disputeStatus, (_disputeId)),
      abi.encode(IOracle.DisputeStatus.NoResolution)
    );

    // Check: does it revert if the dispute is already resolved?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_AlreadyResolved.selector);
    module.commitVote(mockRequest, mockDispute, _commitment, _createAccessControl(address(this)));
  }

  /**
   * @notice Test that `commitVote` reverts if called with `_disputeId` of a dispute that has already been won.
   */
  function test_revertIfWon(bytes32 _commitment) public {
    // Computer proper IDs
    bytes32 _requestId = _getId(mockRequest);
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));
    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Won)
    );

    // Check: does it revert if the dispute is already resolved?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_AlreadyResolved.selector);
    module.commitVote(mockRequest, mockDispute, _commitment, _createAccessControl(address(this)));
  }

  /**
   * @notice Test that `commitVote` reverts if called with `_disputeId` of an already resolved dispute.
   */
  function test_revertIfAlreadyResolved(bytes32 _commitment) public {
    // Computer proper IDs
    bytes32 _requestId = _getId(mockRequest);
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));
    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Lost)
    );

    // Check: does it revert if the dispute is already resolved?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_AlreadyResolved.selector);
    module.commitVote(mockRequest, mockDispute, _commitment, _createAccessControl(address(this)));
  }

  /**
   * @notice Test that `commitVote` reverts if called with `_disputeId` of a non-escalated dispute.
   */
  function test_revertIfNotEscalated(bytes32 _commitment) public {
    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));
    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    // Check: reverts if dispute is not escalated? == no escalation data
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_DisputeNotEscalated.selector);
    module.commitVote(mockRequest, _dispute, _commitment, _createAccessControl(address(this)));
  }

  /**
   * @notice Test that `commitVote` reverts if called outside of the committing time window.
   */
  function test_revertIfCommittingPhaseOver(uint256 _timestamp, bytes32 _commitment) public {
    _timestamp = bound(_timestamp, 140_000, type(uint96).max);

    // Set mock request data
    mockRequest.resolutionModuleData = abi.encode(
      IPrivateERC20ResolutionModule.RequestParameters({
        accountingExtension: IAccountingExtension(makeAddr('AccountingExtension')),
        votingToken: token,
        minVotesForQuorum: 1,
        committingTimeWindow: 40_000,
        revealingTimeWindow: 40_000
      })
    );

    // Compute proper IDs
    bytes32 _requestId = _getId(mockRequest);
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Store mock escalation data with startTime 100_000
    module.forTest_setStartTime(_disputeId, 100_000);

    // Warp to invalid timestamp for commitment
    vm.warp(_timestamp);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));
    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    // Check: does it revert if the committing phase is over?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_CommittingPhaseOver.selector);
    module.commitVote(mockRequest, mockDispute, _commitment, _createAccessControl(address(this)));
  }
}

contract PrivateERC20ResolutionModule_Unit_RevealVote is BaseTest {
  /**
   * @notice Test revealing votes with proper timestamp, dispute status and commitment data.
   */
  function test_revealVote(uint256 _amountOfVotes, bytes32 _salt, address _voter) public {
    // Set mock request data
    mockRequest.resolutionModuleData = abi.encode(
      IPrivateERC20ResolutionModule.RequestParameters({
        accountingExtension: IAccountingExtension(makeAddr('AccountingExtension')),
        votingToken: token,
        minVotesForQuorum: 1,
        committingTimeWindow: 40_000,
        revealingTimeWindow: 40_000
      })
    );

    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));

    // Store mock escalation data with startTime 100_000
    module.forTest_setStartTime(_disputeId, 100_000);

    // Store commitment
    vm.prank(_voter);
    bytes32 _commitment = module.computeCommitment(_disputeId, _amountOfVotes, _salt);
    module.forTest_setVoterData(
      _disputeId, _voter, IPrivateERC20ResolutionModule.VoterData({numOfVotes: 0, commitment: _commitment})
    );

    // Mock and expect IERC20.transferFrom to be called
    _mockAndExpect(
      address(token), abi.encodeCall(IERC20.transferFrom, (_voter, address(module), _amountOfVotes)), abi.encode()
    );

    // Warp to revealing phase
    vm.warp(150_000);

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true);
    emit VoteRevealed(_voter, _disputeId, _amountOfVotes);

    vm.prank(_voter);
    module.revealVote(mockRequest, _dispute, _amountOfVotes, _salt, _createAccessControl(address(_voter)));

    (, uint256 _totalVotes) = module.escalations(_disputeId);
    // Check: is totalVotes updated?
    assertEq(_totalVotes, _amountOfVotes);

    // Check: is voter data properly updated?
    IPrivateERC20ResolutionModule.VoterData memory _voterData = module.forTest_getVoterData(_disputeId, _voter);
    assertEq(_voterData.numOfVotes, _amountOfVotes);
  }

  /**
   * @notice Test that `revealVote` reverts if the dispute body is invalid.
   */
  function test_revertIfInvalidDisputeBody(uint256 _numberOfVotes, bytes32 _salt) public {
    // Check: does it revert if the dispute body is invalid?
    mockDispute.requestId = bytes32(0);
    vm.expectRevert(ValidatorLib.ValidatorLib_InvalidDisputeBody.selector);
    module.revealVote(mockRequest, mockDispute, _numberOfVotes, _salt, _createAccessControl(address(this)));
  }

  /**
   * @notice Test that `revealVote` reverts if called with `_disputeId` of a non-escalated dispute.
   */
  function test_revertIfNotEscalated(uint256 _numberOfVotes, bytes32 _salt) public {
    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));

    // Check: does it revert if the dispute is not escalated?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_DisputeNotEscalated.selector);
    module.revealVote(mockRequest, mockDispute, _numberOfVotes, _salt, _createAccessControl(address(this)));
  }

  /**
   * @notice Test that `revealVote` reverts if called outside the revealing time window.
   */
  function test_revertIfInvalidPhase(uint256 _numberOfVotes, bytes32 _salt, uint256 _timestamp) public {
    vm.assume(_timestamp >= 100_000 && (_timestamp <= 140_000 || _timestamp > 180_000));

    // Set mock request data
    mockRequest.resolutionModuleData = abi.encode(
      IPrivateERC20ResolutionModule.RequestParameters({
        accountingExtension: IAccountingExtension(makeAddr('AccountingExtension')),
        votingToken: token,
        minVotesForQuorum: 1,
        committingTimeWindow: 40_000,
        revealingTimeWindow: 40_000
      })
    );

    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, _disputeId), abi.encode(1));

    module.forTest_setStartTime(_disputeId, 100_000);

    // Jump to timestamp
    vm.warp(_timestamp);

    if (_timestamp <= 140_000) {
      // Check: does it revert if trying to reveal during the committing phase?
      vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_OnGoingCommittingPhase.selector);
      module.revealVote(mockRequest, _dispute, _numberOfVotes, _salt, _createAccessControl(address(this)));
    } else {
      // Check: does it revert if trying to reveal after the revealing phase?
      vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_RevealingPhaseOver.selector);
      module.revealVote(mockRequest, _dispute, _numberOfVotes, _salt, _createAccessControl(address(this)));
    }
  }

  /**
   * @notice Test that `revealVote` reverts if called with revealing parameters (`_disputeId`, `_numberOfVotes`, `_salt`)
   * that do not compute to the stored commitment.
   */
  function test_revertIfFalseCommitment(
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

    // Set mock request data
    mockRequest.resolutionModuleData = abi.encode(
      IPrivateERC20ResolutionModule.RequestParameters({
        accountingExtension: IAccountingExtension(makeAddr('AccountingExtension')),
        votingToken: token,
        minVotesForQuorum: 1,
        committingTimeWindow: 40_000,
        revealingTimeWindow: 40_000
      })
    );

    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));

    module.forTest_setStartTime(_disputeId, 100_000);

    vm.warp(150_000);

    vm.startPrank(_voter);
    bytes32 _commitment = module.computeCommitment(_disputeId, _amountOfVotes, _salt);
    module.forTest_setVoterData(
      _disputeId, _voter, IPrivateERC20ResolutionModule.VoterData({numOfVotes: 0, commitment: _commitment})
    );

    // Check: does it revert if the commitment is not valid? (wrong salt)
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_WrongRevealData.selector);
    module.revealVote(mockRequest, _dispute, _amountOfVotes, _wrongSalt, _createAccessControl());

    // Check: does it revert if the commitment is not valid? (wrong amount of votes)
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_WrongRevealData.selector);
    module.revealVote(mockRequest, _dispute, _wrongAmountOfVotes, _salt, _createAccessControl());

    vm.stopPrank();

    // Check: does it revert if the commitment is not valid? (wrong voter)
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_WrongRevealData.selector);
    vm.prank(_wrongVoter);
    module.revealVote(mockRequest, _dispute, _amountOfVotes, _salt, _createAccessControl(_wrongVoter));
  }
}

contract PrivateERC20ResolutionModule_Unit_ResolveDispute is BaseTest {
  /**
   * @notice Test that a dispute is resolved, the tokens are transferred back to the voters and the dispute status updated.
   */
  function test_resolveDispute(uint16 _minVotesForQuorum) public {
    // Set request data
    mockRequest.resolutionModuleData = abi.encode(
      IPrivateERC20ResolutionModule.RequestParameters({
        accountingExtension: IAccountingExtension(makeAddr('AccountingExtension')),
        votingToken: token,
        minVotesForQuorum: _minVotesForQuorum,
        committingTimeWindow: 40_000,
        revealingTimeWindow: 40_000
      })
    );

    // Compute proper ids
    bytes32 _requestId = _getId(mockRequest);
    mockResponse.requestId = _requestId;
    bytes32 _responseId = _getId(mockResponse);
    mockDispute.requestId = _requestId;
    mockDispute.responseId = _responseId;
    bytes32 _disputeId = _getId(mockDispute);

    module.forTest_setStartTime(_disputeId, 100_000);

    // Store escalation data with startTime 100_000 and votes 0
    uint256 _votersAmount = 5;
    // Make 5 addresses cast 100 votes each
    uint256 _totalVotesCast = _populateVoters(mockRequest, mockDispute, _votersAmount, 100);

    // Warp to resolving phase
    vm.warp(190_000);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Won)
    );

    // Check: does it revert if the dispute status is != None?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_AlreadyResolved.selector);
    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);

    // Mock and expect token transfers (should happen always)
    for (uint256 _i = 1; _i <= _votersAmount;) {
      _mockAndExpect(address(token), abi.encodeCall(IERC20.transfer, (vm.addr(_i), 100)), abi.encode());
      unchecked {
        ++_i;
      }
    }

    // If quorum reached, check for dispute status update and event emission
    IOracle.DisputeStatus _newStatus =
      _totalVotesCast >= _minVotesForQuorum ? IOracle.DisputeStatus.Won : IOracle.DisputeStatus.Lost;

    // Mock and expect IOracle.updateDisputeStatus to be called
    _mockAndExpect(
      address(oracle),
      abi.encodeCall(
        IOracle.updateDisputeStatus,
        (mockRequest, mockResponse, mockDispute, _newStatus, _createAccessControl(address(module)))
      ),
      abi.encode()
    );

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true);
    emit DisputeResolved(_requestId, _disputeId, _newStatus);

    // Check: does it revert if called by address != oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);
    module.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);

    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Test that `resolveDispute` reverts if called during committing or revealing time window.
   */
  function test_revertIfWrongPhase(uint256 _timestamp) public {
    _timestamp = bound(_timestamp, 1, 1_000_000);

    // Set request data
    mockRequest.resolutionModuleData = abi.encode(
      IPrivateERC20ResolutionModule.RequestParameters({
        accountingExtension: IAccountingExtension(makeAddr('AccountingExtension')),
        votingToken: token,
        minVotesForQuorum: 1,
        committingTimeWindow: 500_000,
        revealingTimeWindow: 1_000_000
      })
    );

    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    module.forTest_setStartTime(_disputeId, 1);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    // Jump to timestamp
    vm.warp(_timestamp);

    // fixme : refactor this test
    if (_timestamp <= 500_000) {
      // Check: does it revert if trying to resolve during the committing phase?
      vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_OnGoingCommittingPhase.selector);
      vm.prank(address(oracle));
      module.resolveDispute(_disputeId, mockRequest, _response, _dispute);
    } else {
      // Check: does it revert if trying to resolve during the revealing phase?
      vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_OnGoingRevealingPhase.selector);
      vm.prank(address(oracle));
      module.resolveDispute(_disputeId, mockRequest, _response, _dispute);
    }
  }

  function test_revertIfActive() public {
    // Set request data
    mockRequest.resolutionModuleData = abi.encode(
      IPrivateERC20ResolutionModule.RequestParameters({
        accountingExtension: IAccountingExtension(makeAddr('AccountingExtension')),
        votingToken: token,
        minVotesForQuorum: 1,
        committingTimeWindow: 500_000,
        revealingTimeWindow: 1_000_000
      })
    );

    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    module.forTest_setStartTime(_disputeId, 1);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Active)
    );

    // Check: does it revert if the dispute is already resolved?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_AlreadyResolved.selector);
    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, _response, _dispute);
  }

  function test_revertIfWon() public {
    // Set request data
    mockRequest.resolutionModuleData = abi.encode(
      IPrivateERC20ResolutionModule.RequestParameters({
        accountingExtension: IAccountingExtension(makeAddr('AccountingExtension')),
        votingToken: token,
        minVotesForQuorum: 1,
        committingTimeWindow: 500_000,
        revealingTimeWindow: 1_000_000
      })
    );

    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    module.forTest_setStartTime(_disputeId, 1);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Won)
    );

    // Check: does it revert if the dispute is already resolved?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_AlreadyResolved.selector);
    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, _response, _dispute);
  }

  function test_revertIfLost() public {
    // Set request data
    mockRequest.resolutionModuleData = abi.encode(
      IPrivateERC20ResolutionModule.RequestParameters({
        accountingExtension: IAccountingExtension(makeAddr('AccountingExtension')),
        votingToken: token,
        minVotesForQuorum: 1,
        committingTimeWindow: 500_000,
        revealingTimeWindow: 1_000_000
      })
    );

    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    module.forTest_setStartTime(_disputeId, 1);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Lost)
    );

    // Check: does it revert if the dispute is already resolved?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_AlreadyResolved.selector);
    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, _response, _dispute);
  }

  function test_revertIfNonResolve() public {
    // Set request data
    mockRequest.resolutionModuleData = abi.encode(
      IPrivateERC20ResolutionModule.RequestParameters({
        accountingExtension: IAccountingExtension(makeAddr('AccountingExtension')),
        votingToken: token,
        minVotesForQuorum: 1,
        committingTimeWindow: 500_000,
        revealingTimeWindow: 1_000_000
      })
    );

    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    module.forTest_setStartTime(_disputeId, 1);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle),
      abi.encodeCall(IOracle.disputeStatus, (_disputeId)),
      abi.encode(IOracle.DisputeStatus.NoResolution)
    );

    // Check: does it revert if the dispute is already resolved?
    vm.expectRevert(IPrivateERC20ResolutionModule.PrivateERC20ResolutionModule_AlreadyResolved.selector);
    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, _response, _dispute);
  }
}
