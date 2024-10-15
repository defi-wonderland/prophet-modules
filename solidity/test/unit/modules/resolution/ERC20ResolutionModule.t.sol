// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import {IModule} from '@defi-wonderland/prophet-core/solidity/interfaces/IModule.sol';
import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';
import {ValidatorLib} from '@defi-wonderland/prophet-core/solidity/libraries/ValidatorLib.sol';

import {
  ERC20ResolutionModule,
  IERC20ResolutionModule
} from '../../../../contracts/modules/resolution/ERC20ResolutionModule.sol';

import {IAccountingExtension} from '../../../../interfaces/extensions/IAccountingExtension.sol';

contract ForTest_ERC20ResolutionModule is ERC20ResolutionModule {
  using EnumerableSet for EnumerableSet.AddressSet;

  constructor(IOracle _oracle) ERC20ResolutionModule(_oracle) {}

  function forTest_setStartTime(bytes32 _disputeId, uint256 _startTime) public {
    escalations[_disputeId] = IERC20ResolutionModule.Escalation({
      startTime: _startTime,
      totalVotes: 0 // Initial amount of votes
    });
  }

  function forTest_setVotes(bytes32 _disputeId, address _voter, uint256 _amountOfVotes) public {
    votes[_disputeId][_voter] = _amountOfVotes;
  }

  function forTest_castVote(bytes32 _disputeId, address _voter, uint256 _numberOfVotes) public {
    votes[_disputeId][_voter] += _numberOfVotes;
    _voters[_disputeId].add(_voter);
    escalations[_disputeId].totalVotes += _numberOfVotes;
  }
}

contract BaseTest is Test, Helpers {
  // The target contract
  ForTest_ERC20ResolutionModule public module;
  // A mock oracle
  IOracle public oracle = IOracle(_mockContract('Oracle'));
  // A mock token
  IERC20 public token = IERC20(_mockContract('Token'));
  // Mock accounting extension
  IAccountingExtension public accountingExtension = IAccountingExtension(_mockContract('AccountingExtension'));

  uint256 public votingTimeWindow = 40_000;

  // Events
  event VoteCast(address _voter, bytes32 _disputeId, uint256 _numberOfVotes);
  event VotingPhaseStarted(uint256 _startTime, bytes32 _disputeId);
  event DisputeResolved(bytes32 indexed _requestId, bytes32 indexed _disputeId, IOracle.DisputeStatus _status);
  event VoteClaimed(address _voter, bytes32 _disputeId, uint256 _amount);

  /**
   * @notice Deploy the target and mock oracle extension
   */
  function setUp() public virtual {
    module = new ForTest_ERC20ResolutionModule(oracle);
  }

  /**
   * @dev Helper function to cast votes.
   */
  function _populateVoters(bytes32 _disputeId, uint256 _amountOfVoters, uint256 _amountOfVotes) internal {
    for (uint256 _i = 1; _i <= _amountOfVoters; _i++) {
      vm.warp(120_000);
      module.forTest_castVote(_disputeId, vm.addr(_i), _amountOfVotes);
    }
  }
}

contract ERC20ResolutionModule_Unit_ModuleData is BaseTest {
  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleName() public view {
    assertEq(module.moduleName(), 'ERC20ResolutionModule');
  }

  /**
   * @notice Test that the decodeRequestData function returns the correct values
   */
  function test_decodeRequestData_returnsCorrectData(
    address _token,
    uint256 _minVotesForQuorum,
    uint256 _votingTimeWindow
  ) public view {
    // Mock data
    bytes memory _requestData = abi.encode(address(accountingExtension), _token, _minVotesForQuorum, _votingTimeWindow);

    // Test: decode the given request data
    IERC20ResolutionModule.RequestParameters memory _params = module.decodeRequestData(_requestData);

    // Check: decoded values match original values?
    assertEq(address(_params.accountingExtension), address(accountingExtension));
    assertEq(address(_params.votingToken), _token);
    assertEq(_params.minVotesForQuorum, _minVotesForQuorum);
    assertEq(_params.timeUntilDeadline, _votingTimeWindow);
  }

  /**
   * @notice Test that the validateParameters function correctly checks the parameters
   */
  function test_validateParameters(IERC20ResolutionModule.RequestParameters calldata _params) public view {
    if (
      address(_params.accountingExtension) == address(0) || address(_params.votingToken) == address(0)
        || _params.minVotesForQuorum == 0 || _params.timeUntilDeadline == 0
    ) {
      assertFalse(module.validateParameters(abi.encode(_params)));
    } else {
      assertTrue(module.validateParameters(abi.encode(_params)));
    }
  }
}

contract ERC20ResolutionModule_Unit_StartResolution is BaseTest {
  /**
   * @notice Test that the `startResolution` is correctly called and the voting phase is started
   */
  function test_revertIfNotOracle(bytes32 _disputeId) public {
    // Check: does revert if called by address != oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);
    module.startResolution(_disputeId, mockRequest, mockResponse, mockDispute);
  }

  function test_setsStartTime(bytes32 _disputeId) public {
    vm.prank(address(oracle));
    module.startResolution(_disputeId, mockRequest, mockResponse, mockDispute);

    // Check: `startTime` is set to block.timestamp?
    (uint256 _startTime,) = module.escalations(_disputeId);
    assertEq(_startTime, block.timestamp);
  }

  function test_emitsEvent(bytes32 _disputeId) public {
    // Check: emits VotingPhaseStarted event?
    vm.expectEmit(true, true, true, true, address(module));
    emit VotingPhaseStarted(block.timestamp, _disputeId);

    vm.prank(address(oracle));
    module.startResolution(_disputeId, mockRequest, mockResponse, mockDispute);
  }
}

contract ERC20ResolutionModule_Unit_CastVote is BaseTest {
  /**
   * @notice Test casting votes in valid voting time window.
   */
  function test_castVote(uint256 _amountOfVotes, address _voter) public {
    uint256 _minVotesForQuorum = 1;

    mockRequest.resolutionModuleData = abi.encode(
      IERC20ResolutionModule.RequestParameters({
        accountingExtension: accountingExtension,
        votingToken: token,
        minVotesForQuorum: _minVotesForQuorum,
        timeUntilDeadline: votingTimeWindow
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

    // Mock and expect the token transferFrom
    _mockAndExpect(
      address(token), abi.encodeCall(IERC20.transferFrom, (_voter, address(module), _amountOfVotes)), abi.encode(true)
    );

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    // Warp to voting phase
    vm.warp(130_000);

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true);
    emit VoteCast(_voter, _disputeId, _amountOfVotes);

    vm.prank(_voter);
    module.castVote(mockRequest, _dispute, _amountOfVotes);

    (, uint256 _totalVotes) = module.escalations(_disputeId);
    // Check: totalVotes is updated?
    assertEq(_totalVotes, _amountOfVotes);

    // Check: voter data is updated?
    assertEq(module.votes(_disputeId, _voter), _amountOfVotes);
  }

  /**
   * @notice Test that `castVote` reverts if the dispute body is invalid.
   */
  function test_revertIfInvalidDisputeBody(uint256 _numberOfVotes) public {
    // Check: does it revert if the dispute body is invalid?
    mockDispute.requestId = bytes32(0);
    vm.expectRevert(ValidatorLib.ValidatorLib_InvalidDisputeBody.selector);
    module.castVote(mockRequest, mockDispute, _numberOfVotes);
  }

  /**
   * @notice Test that `castVote` reverts if called with `_disputeId` of a non-escalated dispute.
   */
  function test_revertIfNotEscalated(uint256 _numberOfVotes) public {
    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));

    // Check: reverts if called with `_disputeId` of a non-escalated dispute?
    vm.expectRevert(IERC20ResolutionModule.ERC20ResolutionModule_DisputeNotEscalated.selector);
    module.castVote(mockRequest, _dispute, _numberOfVotes);
  }

  /**
   * @notice Test that `castVote` reverts if called with `_disputeId` of an already resolved dispute.
   */
  function test_revertIfAlreadyResolved(uint256 _amountOfVotes, uint256 _votingTimeWindow) public {
    mockRequest.resolutionModuleData = abi.encode(
      IERC20ResolutionModule.RequestParameters({
        accountingExtension: accountingExtension,
        votingToken: token,
        minVotesForQuorum: _amountOfVotes,
        timeUntilDeadline: _votingTimeWindow
      })
    );

    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Won)
    );

    module.forTest_setStartTime(_disputeId, block.timestamp);

    // Check: reverts if dispute is already resolved?
    vm.expectRevert(IERC20ResolutionModule.ERC20ResolutionModule_AlreadyResolved.selector);
    module.castVote(mockRequest, _dispute, _amountOfVotes);
  }

  /**
   * @notice Test that `castVote` reverts if called outside the voting time window.
   */
  function test_revertIfVotingPhaseOver(uint256 _numberOfVotes, uint256 _timestamp) public {
    vm.assume(_timestamp > 140_000);
    uint256 _minVotesForQuorum = 1;

    mockRequest.resolutionModuleData = abi.encode(
      IERC20ResolutionModule.RequestParameters({
        accountingExtension: accountingExtension,
        votingToken: token,
        minVotesForQuorum: _minVotesForQuorum,
        timeUntilDeadline: votingTimeWindow
      })
    );

    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    module.forTest_setStartTime(_disputeId, 100_000);

    // Jump to timestamp
    vm.warp(_timestamp);

    // Check: reverts if trying to cast vote after voting phase?
    vm.expectRevert(IERC20ResolutionModule.ERC20ResolutionModule_VotingPhaseOver.selector);
    module.castVote(mockRequest, _dispute, _numberOfVotes);
  }
}

contract ERC20ResolutionModule_Unit_ResolveDispute is BaseTest {
  /**
   * @notice Test that a dispute is resolved, the tokens are transferred back to the voters and the dispute status updated.
   */
  function test_resolveDispute(uint16 _minVotesForQuorum) public {
    mockRequest.resolutionModuleData = abi.encode(
      IERC20ResolutionModule.RequestParameters({
        accountingExtension: accountingExtension,
        votingToken: token,
        minVotesForQuorum: _minVotesForQuorum,
        timeUntilDeadline: votingTimeWindow
      })
    );
    bytes32 _requestId = _getId(mockRequest);
    mockDispute.requestId = _requestId;
    bytes32 _disputeId = _getId(mockDispute);

    // Store escalation data with `startTime` 100_000 and votes 0
    module.forTest_setStartTime(_disputeId, 100_000);

    uint256 _votersAmount = 5;

    // Make 5 addresses cast 100 votes each
    uint256 _totalVotesCast = 100 * _votersAmount;
    _populateVoters(_disputeId, _votersAmount, 100);

    // Warp to resolving phase
    vm.warp(150_000);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Won)
    );

    // Check: does it revert if the dispute status is != Escalated?
    vm.expectRevert(IERC20ResolutionModule.ERC20ResolutionModule_AlreadyResolved.selector);
    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);

    // Mock and expect IOracle.disputeStatus to be called
    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    // If quorum reached, check for dispute status update and event emission
    IOracle.DisputeStatus _newStatus =
      _totalVotesCast >= _minVotesForQuorum ? IOracle.DisputeStatus.Won : IOracle.DisputeStatus.Lost;

    // Mock and expect IOracle.updateDisputeStatus to be called
    _mockAndExpect(
      address(oracle),
      abi.encodeCall(IOracle.updateDisputeStatus, (mockRequest, mockResponse, mockDispute, _newStatus)),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true);
    emit DisputeResolved(_requestId, _disputeId, _newStatus);

    // Check: does revert if called by address != oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);
    module.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);

    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);
  }

  /**
   * @notice Test that `resolveDispute` reverts if called during voting phase.
   */
  function test_revertIfOnGoingVotePhase(uint256 _timestamp) public {
    _timestamp = bound(_timestamp, 500_000, 999_999);

    uint256 _minVotesForQuorum = 1;
    uint256 _votingTimeWindow = 500_000;

    mockRequest.resolutionModuleData = abi.encode(
      IERC20ResolutionModule.RequestParameters({
        accountingExtension: accountingExtension,
        votingToken: token,
        minVotesForQuorum: _minVotesForQuorum,
        timeUntilDeadline: _votingTimeWindow
      })
    );
    mockDispute.requestId = _getId(mockRequest);
    bytes32 _disputeId = _getId(mockDispute);
    module.forTest_setStartTime(_disputeId, 500_000);

    _mockAndExpect(
      address(oracle), abi.encodeCall(IOracle.disputeStatus, (_disputeId)), abi.encode(IOracle.DisputeStatus.Escalated)
    );

    // Jump to timestamp
    vm.warp(_timestamp);

    // Check: reverts if trying to resolve during voting phase?
    vm.expectRevert(IERC20ResolutionModule.ERC20ResolutionModule_OnGoingVotingPhase.selector);
    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);
  }
}

contract ERC20ResolutionModule_Unit_ClaimVote is BaseTest {
  /**
   * @notice Reverts if the dispute body is invalid
   */
  function test_revertIfInvalidDisputeBody() public {
    // Check: does it revert if the dispute body is invalid?
    mockDispute.requestId = bytes32(0);
    vm.expectRevert(ValidatorLib.ValidatorLib_InvalidDisputeBody.selector);
    module.claimVote(mockRequest, mockDispute);
  }

  /**
   * @notice Reverts if the vote is still ongoing
   */
  function test_revertIfVoteIsOnGoing(address _voter) public {
    mockRequest.resolutionModuleData = abi.encode(
      IERC20ResolutionModule.RequestParameters({
        accountingExtension: accountingExtension,
        votingToken: token,
        minVotesForQuorum: 1,
        timeUntilDeadline: 1000
      })
    );

    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));
    module.forTest_setStartTime(_getId(mockDispute), block.timestamp);

    // Expect an error to be thrown
    vm.expectRevert(IERC20ResolutionModule.ERC20ResolutionModule_OnGoingVotingPhase.selector);

    // Claim the refund
    vm.prank(_voter);
    module.claimVote(mockRequest, _dispute);
  }

  /**
   * @notice Releases the funds
   */
  function test_releasesFunds(address _voter, uint256 _amount) public {
    mockRequest.resolutionModuleData = abi.encode(
      IERC20ResolutionModule.RequestParameters({
        accountingExtension: accountingExtension,
        votingToken: token,
        minVotesForQuorum: 1,
        timeUntilDeadline: 1
      })
    );

    // Compute proper IDs
    IOracle.Response memory _response = _getResponse(mockRequest, proposer);
    IOracle.Dispute memory _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(address(oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(1));

    // Expect the bond to be released
    _mockAndExpect(address(token), abi.encodeCall(IERC20.transfer, (_voter, _amount)), abi.encode(true));

    vm.warp(block.timestamp + 1000);

    module.forTest_setVotes(_disputeId, _voter, _amount);

    // Expect the event to be emitted
    _expectEmit(address(module));
    emit VoteClaimed(_voter, _disputeId, _amount);

    // Claim the refund
    vm.prank(_voter);
    module.claimVote(mockRequest, _dispute);
  }
}

contract ERC20ResolutionModule_Unit_GetVoters is BaseTest {
  /**
   * @notice Test that `getVoters` returns an array of addresses of users that have voted.
   */
  function test_getVoters(bytes32 _disputeId) public {
    bytes32 _requestId = _getId(mockRequest);
    mockDispute.requestId = _requestId;

    // Store escalation data with `startTime` 100_000 and votes 0
    module.forTest_setStartTime(_disputeId, 100_000);
    uint256 _votersAmount = 3;

    // Make 3 addresses cast 100 votes each
    _populateVoters(_disputeId, _votersAmount, 100);

    address[] memory _votersArray = module.getVoters(_disputeId);

    for (uint256 _i = 1; _i <= _votersAmount; _i++) {
      assertEq(_votersArray[_i - 1], vm.addr(_i));
    }
  }
}
