// SPDX-License-Identifier: MIT
pragma solidity >=0.8.16 <0.9.0;

import {IOracle} from '../IOracle.sol';
import {IResolutionModule} from './IResolutionModule.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IBondEscalationAccounting} from '../extensions/IBondEscalationAccounting.sol';

interface IBondEscalationResolutionModule is IResolutionModule {
  enum InequalityStatus {
    Unstarted,
    Equalized,
    ForTurnToEqualize,
    AgainstTurnToEqualize
  }

  enum Resolution {
    Unresolved,
    DisputerWon,
    DisputerLost,
    NoResolution
  }

  struct PledgeData {
    address pledger;
    uint256 pledges;
  }

  struct InequalityData {
    InequalityStatus inequalityStatus;
    uint256 time;
  }

  struct EscalationData {
    Resolution resolution;
    uint128 startTime;
    uint256 pledgesFor;
    uint256 pledgesAgainst;
  }

  // TODO: should I add requestId as a param?
  event DisputeResolved(bytes32 indexed _disputeId, IOracle.DisputeStatus _status);
  event DisputeEscalated(bytes32 indexed _disputeId, bytes32 indexed requestId);
  event PledgedForDispute(
    address indexed _pledger, bytes32 indexed _requestId, bytes32 indexed _disputeId, uint256 _pledgedAmount
  );
  event PledgedAgainstDispute(
    address indexed _pledger, bytes32 indexed _requestId, bytes32 indexed _disputeId, uint256 _pledgedAmount
  );

  error BondEscalationResolutionModule_OnlyDisputeModule();
  error BondEscalationResolutionModule_AlreadyResolved();
  error BondEscalationResolutionModule_NotResolved();
  error BondEscalationResolutionModule_NotEscalated();
  error BondEscalationResolutionModule_PledgingPhaseOver();
  error BondEscalationResolutionModule_PledgingPhaseNotOver();
  error BondEscalationResolutionModule_MustBeResolved();
  error BondEscalationResolutionModule_AgainstTurnToEqualize();
  error BondEscalationResolutionModule_ForTurnToEqualize();

  function escalationData(bytes32 _disputeId)
    external
    view
    returns (Resolution _resolution, uint128 _startTime, uint256 _votesFor, uint256 _votesAgainst);
  function inequalityData(bytes32 _disputeId) external view returns (InequalityStatus _inequalityStatus, uint256 _time);

  function decodeRequestData(bytes32 _requestId)
    external
    view
    returns (
      IBondEscalationAccounting _accountingExtension,
      IERC20 _token,
      uint256 _percentageDiff,
      uint256 _pledgeThreshold,
      uint256 _timeUntilDeadline,
      uint256 _timeToBreakInequality
    );
}