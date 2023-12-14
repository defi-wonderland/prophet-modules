// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {Helpers} from '../../../utils/Helpers.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';
import {FixedPointMathLib} from 'solmate/utils/FixedPointMathLib.sol';

import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IModule} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IModule.sol';

import {
  BondEscalationResolutionModule,
  IBondEscalationResolutionModule
} from '../../../../contracts/modules/resolution/BondEscalationResolutionModule.sol';
import {IBondEscalationAccounting} from '../../../../interfaces/extensions/IBondEscalationAccounting.sol';

/**
 * @dev Harness to set an entry in the requestData mapping, without triggering setup request hooks
 */

contract ForTest_BondEscalationResolutionModule is BondEscalationResolutionModule {
  constructor(IOracle _oracle) BondEscalationResolutionModule(_oracle) {}

  function forTest_setEscalation(
    bytes32 _disputeId,
    IBondEscalationResolutionModule.Resolution _resolution,
    uint128 _startTime,
    uint256 _pledgesFor,
    uint256 _pledgesAgainst
  ) public {
    BondEscalationResolutionModule.Escalation memory _escalation =
      IBondEscalationResolutionModule.Escalation(_resolution, _startTime, _pledgesFor, _pledgesAgainst);
    escalations[_disputeId] = _escalation;
  }

  function forTest_setInequalityData(
    bytes32 _disputeId,
    IBondEscalationResolutionModule.InequalityStatus _inequalityStatus,
    uint256 _time
  ) public {
    BondEscalationResolutionModule.InequalityData memory _inequalityData =
      IBondEscalationResolutionModule.InequalityData(_inequalityStatus, _time);
    inequalityData[_disputeId] = _inequalityData;
  }

  function forTest_setPledgesFor(bytes32 _disputeId, address _pledger, uint256 _pledge) public {
    pledgesForDispute[_disputeId][_pledger] = _pledge;
  }

  function forTest_setPledgesAgainst(bytes32 _disputeId, address _pledger, uint256 _pledge) public {
    pledgesAgainstDispute[_disputeId][_pledger] = _pledge;
  }
}

/**
 * @title Bonded Escalation Resolution Module Unit tests
 */

contract BaseTest is Test, Helpers {
  // The target contract
  ForTest_BondEscalationResolutionModule public module;
  // A mock oracle
  IOracle public oracle;
  // A mock accounting extension
  IBondEscalationAccounting public accounting;
  // A mock token
  IERC20 public token;
  // Mock EOA pledgerFor
  address public pledgerFor = makeAddr('pledgerFor');
  // Mock EOA pledgerAgainst
  address public pledgerAgainst = makeAddr('pledgerAgainst');
  // Mock percentageDiff
  uint256 public percentageDiff = 20;
  // Mock pledge threshold
  uint256 public pledgeThreshold = 1;
  // Mock time until main deadline
  uint256 public timeUntilDeadline = 1001;
  // Mock time to break inequality
  uint256 public timeToBreakInequality = 5000;
  // Mock the request parameters
  IBondEscalationResolutionModule.RequestParameters public requestParameters;

  // Events
  event DisputeResolved(bytes32 indexed _requestId, bytes32 indexed _disputeId, IOracle.DisputeStatus _status);
  event ResolutionStarted(bytes32 indexed _requestId, bytes32 indexed _disputeId);
  event PledgedForDispute(
    address indexed _pledger, bytes32 indexed _requestId, bytes32 indexed _disputeId, uint256 _pledgedAmount
  );
  event PledgedAgainstDispute(
    address indexed _pledger, bytes32 indexed _requestId, bytes32 indexed _disputeId, uint256 _pledgedAmount
  );
  event PledgeClaimed(
    bytes32 indexed _requestId,
    bytes32 indexed _disputeId,
    address indexed _pledger,
    IERC20 _token,
    uint256 _pledgeReleased,
    IBondEscalationResolutionModule.Resolution _resolution
  );

  /**
   * @notice Deploy the target and mock oracle+accounting extension
   */
  function setUp() public virtual {
    oracle = IOracle(makeAddr('Oracle'));
    vm.etch(address(oracle), hex'069420');

    accounting = IBondEscalationAccounting(makeAddr('AccountingExtension'));
    vm.etch(address(accounting), hex'069420');

    token = IERC20(makeAddr('ERC20'));
    vm.etch(address(token), hex'069420');

    // Avoid starting at 0 for time sensitive tests
    vm.warp(123_456);

    module = new ForTest_BondEscalationResolutionModule(oracle);

    requestParameters.accountingExtension = accounting;
    requestParameters.bondToken = token;
    requestParameters.percentageDiff = percentageDiff;
    requestParameters.pledgeThreshold = pledgeThreshold;
    requestParameters.timeUntilDeadline = timeUntilDeadline;
    requestParameters.timeToBreakInequality = timeToBreakInequality;
  }

  function _createPledgers(
    uint256 _numOfPledgers,
    uint256 _amount
  ) internal returns (address[] memory _pledgers, uint256[] memory _pledgedAmounts) {
    _pledgers = new address[](_numOfPledgers);
    _pledgedAmounts = new uint256[](_numOfPledgers);
    address _pledger;
    uint256 _pledge;

    for (uint256 _i; _i < _numOfPledgers; _i++) {
      _pledger = makeAddr(string.concat('pledger', Strings.toString(_i)));
      _pledgers[_i] = _pledger;
    }

    for (uint256 _j; _j < _numOfPledgers; _j++) {
      _pledge = _amount / (_j + 100);
      _pledgedAmounts[_j] = _pledge;
    }

    return (_pledgers, _pledgedAmounts);
  }

  function _setResolutionModuleData(IBondEscalationResolutionModule.RequestParameters memory _params)
    internal
    returns (bytes32 _requestId, bytes32 _responseId, bytes32 _disputeId)
  {
    mockRequest.resolutionModuleData = abi.encode(_params);
    _requestId = _getId(mockRequest);

    mockResponse.requestId = _requestId;
    _responseId = _getId(mockResponse);

    mockDispute.requestId = _requestId;
    mockDispute.responseId = _responseId;
    _disputeId = _getId(mockDispute);
  }
}

contract BondEscalationResolutionModule_Unit_ModuleData is BaseTest {
  function test_decodeRequestDataReturnTheCorrectData(
    uint256 _percentageDiff,
    uint256 _pledgeThreshold,
    uint256 _timeUntilDeadline,
    uint256 _timeToBreakInequality
  ) public {
    // Storing fuzzed data
    bytes memory _data =
      abi.encode(accounting, token, _percentageDiff, _pledgeThreshold, _timeUntilDeadline, _timeToBreakInequality);
    IBondEscalationResolutionModule.RequestParameters memory _params = module.decodeRequestData(_data);

    // Check: do the stored values match?
    assertEq(address(accounting), address(_params.accountingExtension));
    assertEq(address(token), address(_params.bondToken));
    assertEq(_percentageDiff, _params.percentageDiff);
    assertEq(_pledgeThreshold, _params.pledgeThreshold);
    assertEq(_timeUntilDeadline, _params.timeUntilDeadline);
    assertEq(_timeToBreakInequality, _params.timeToBreakInequality);
  }

  /**
   * @notice Test that the moduleName function returns the correct name
   */
  function test_moduleName() public {
    assertEq(module.moduleName(), 'BondEscalationResolutionModule');
  }
}

contract BondEscalationResolutionModule_Unit_StartResolution is BaseTest {
  function test_startResolution(IOracle.Request calldata _request) public {
    bytes32 _requestId = _getId(_request);

    mockResponse.requestId = _requestId;
    bytes32 _responseId = _getId(mockResponse);

    mockDispute.requestId = _requestId;
    mockDispute.responseId = _responseId;
    bytes32 _disputeId = _getId(mockDispute);

    // Check: does it revert if the caller is not the Oracle?
    vm.expectRevert(IModule.Module_OnlyOracle.selector);
    module.startResolution(_disputeId, _request, mockResponse, mockDispute);

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit ResolutionStarted(_requestId, _disputeId);

    vm.prank(address(oracle));
    module.startResolution(_disputeId, _request, mockResponse, mockDispute);

    (, uint128 _startTime,,) = module.escalations(_disputeId);
    // Check: is the escalation start time set to block.timestamp?
    assertEq(_startTime, uint128(block.timestamp));
  }
}

contract BondEscalationResolutionModule_Unit_PledgeForDispute is BaseTest {
  uint128 internal _startTime;
  bytes32 internal _disputeId;
  bytes32 internal _requestId;

  function setUp() public override {
    super.setUp();

    // Start at a later time to be able to travel back
    vm.warp(block.timestamp + timeToBreakInequality + 1);

    // block.timestamp < _startTime + _timeUntilDeadline
    _startTime = uint128(block.timestamp - timeUntilDeadline + 1);

    (_requestId,, _disputeId) = _setResolutionModuleData(requestParameters);
  }

  function test_reverts(
    uint256 _pledgeAmount,
    IBondEscalationResolutionModule.RequestParameters memory _params
  ) public assumeFuzzable(address(_params.accountingExtension)) {
    // 1. BondEscalationResolutionModule_NotEscalated
    (_requestId,, _disputeId) = _setResolutionModuleData(_params);

    // Mock escalation with start time 0
    module.forTest_setEscalation(_disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, 0, 0, 0);

    // Check: does it revert if the dispute is not escalated?
    vm.expectRevert(IBondEscalationResolutionModule.BondEscalationResolutionModule_NotEscalated.selector);
    module.pledgeForDispute(mockRequest, mockDispute, _pledgeAmount);

    // 2. BondEscalationResolutionModule_PledgingPhaseOver
    _params.timeUntilDeadline = block.timestamp - 1;
    (_requestId,, _disputeId) = _setResolutionModuleData(_params);

    // Mock escalation with start time 1
    module.forTest_setEscalation(_disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, 1, 0, 0);

    // Check: does it revert if the pledging phase is over?
    vm.expectRevert(IBondEscalationResolutionModule.BondEscalationResolutionModule_PledgingPhaseOver.selector);
    module.pledgeForDispute(mockRequest, mockDispute, _pledgeAmount);

    // 3. BondEscalationResolutionModule_MustBeResolved
    _params.timeUntilDeadline = 10_000;
    _params.timeToBreakInequality = timeToBreakInequality;
    (_requestId,, _disputeId) = _setResolutionModuleData(_params);

    IBondEscalationResolutionModule.InequalityStatus _inequalityStatus =
      IBondEscalationResolutionModule.InequalityStatus.AgainstTurnToEqualize;
    module.forTest_setInequalityData(_disputeId, _inequalityStatus, block.timestamp);

    // Mock escalation with start time equal to current timestamp
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, uint128(block.timestamp), 0, 0
    );

    vm.warp(block.timestamp + _params.timeToBreakInequality);

    // Check: does it revert if inequality timer has passed?
    vm.expectRevert(IBondEscalationResolutionModule.BondEscalationResolutionModule_MustBeResolved.selector);
    module.pledgeForDispute(mockRequest, mockDispute, _pledgeAmount);

    // 4. BondEscalationResolutionModule_AgainstTurnToEqualize
    vm.warp(block.timestamp - _params.timeToBreakInequality - 1); // Not past the deadline anymore
    module.forTest_setInequalityData(_disputeId, _inequalityStatus, block.timestamp);

    // Mock and expect the pledge call
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IBondEscalationAccounting.pledge, (pledgerFor, _requestId, _disputeId, _params.bondToken, _pledgeAmount)
      ),
      abi.encode()
    );

    // Check: does it revert if status == AgainstTurnToEqualize?
    vm.expectRevert(IBondEscalationResolutionModule.BondEscalationResolutionModule_AgainstTurnToEqualize.selector);
    vm.prank(pledgerFor);
    module.pledgeForDispute(mockRequest, mockDispute, _pledgeAmount);
  }

  function test_earlyReturnIfThresholdNotSurpassed(
    uint256 _pledgeAmount,
    IBondEscalationResolutionModule.RequestParameters memory _params
  ) public assumeFuzzable(address(_params.accountingExtension)) {
    vm.assume(_pledgeAmount < type(uint256).max - 1000);

    // _pledgeThreshold > _updatedTotalVotes;
    uint256 _pledgesFor = 1000;
    uint256 _pledgesAgainst = 1000;
    _params.pledgeThreshold = _pledgesFor + _pledgesAgainst + _pledgeAmount + 1;

    // block.timestamp < _inequalityData.time + _timeToBreakInequality
    _params.timeToBreakInequality = timeToBreakInequality;
    _params.timeUntilDeadline = timeUntilDeadline;

    (_requestId,, _disputeId) = _setResolutionModuleData(_params);

    // Set all data
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, _startTime, _pledgesFor, _pledgesAgainst
    );
    module.forTest_setInequalityData(
      _disputeId, IBondEscalationResolutionModule.InequalityStatus.Equalized, block.timestamp
    );

    // Mock and expect IBondEscalationAccounting.pledge to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IBondEscalationAccounting.pledge, (pledgerFor, _requestId, _disputeId, _params.bondToken, _pledgeAmount)
      ),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit PledgedForDispute(pledgerFor, _requestId, _disputeId, _pledgeAmount);

    vm.startPrank(pledgerFor);
    module.pledgeForDispute(mockRequest, mockDispute, _pledgeAmount);

    (,, uint256 _realPledgesFor,) = module.escalations(_disputeId);
    (IBondEscalationResolutionModule.InequalityStatus _status,) = module.inequalityData(_disputeId);

    // Check: is the pledge amount added to the total?
    assertEq(_realPledgesFor, _pledgesFor + _pledgeAmount);
    // Check: is the pledges for dispute amount updated?
    assertEq(module.pledgesForDispute(_disputeId, pledgerFor), _pledgeAmount);
    // Check: is the status properly updated?
    assertEq(uint256(_status), uint256(IBondEscalationResolutionModule.InequalityStatus.Equalized));
  }

  /**
   * @notice Testing _forPercentageDifference >= _scaledPercentageDiffAsInt
   */
  function test_changesStatusIfForSideIsWinning(uint256 _pledgeAmount) public {
    _pledgeAmount = bound(_pledgeAmount, 1, type(uint192).max);

    // I'm setting the values so that the percentage diff is 20% in favor of pledgesFor.
    // In this case, _pledgeAmount will be the entirety of pledgesFor, as if it were the first pledge.
    // Therefore, _pledgeAmount must be 60% of total votes, _pledgesAgainst then should be 40%
    // 40 = 60 * 2 / 3 -> thats why I'm multiplying by 200 and dividing by 300
    uint256 _pledgesFor = 0;
    uint256 _pledgesAgainst = _pledgeAmount * 200 / 300;

    // Set all data
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, _startTime, _pledgesFor, _pledgesAgainst
    );
    module.forTest_setInequalityData(
      _disputeId, IBondEscalationResolutionModule.InequalityStatus.Equalized, block.timestamp
    );

    // Mock and expect IBondEscalationAccounting.pledge to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IBondEscalationAccounting.pledge, (pledgerFor, _requestId, _disputeId, token, _pledgeAmount)),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit PledgedForDispute(pledgerFor, _requestId, _disputeId, _pledgeAmount);

    vm.startPrank(pledgerFor);
    module.pledgeForDispute(mockRequest, mockDispute, _pledgeAmount);

    (,, uint256 _realPledgesFor,) = module.escalations(_disputeId);
    (IBondEscalationResolutionModule.InequalityStatus _status, uint256 _timer) = module.inequalityData(_disputeId);

    // Check: is the pledge amount added to the total?
    assertEq(_realPledgesFor, _pledgesFor + _pledgeAmount);
    // Check: is the pledge for dispute amount updated?
    assertEq(module.pledgesForDispute(_disputeId, pledgerFor), _pledgeAmount);
    // Check: is the status properly updated?
    assertEq(uint256(_status), uint256(IBondEscalationResolutionModule.InequalityStatus.AgainstTurnToEqualize));
    // Check: is the timer properly updated to current timestamp?
    assertEq(uint256(_timer), block.timestamp);
  }

  /**
   * @notice Testing _againstPercentageDifference >= _scaledPercentageDiffAsInt
   */
  function test_changesStatusIfAgainstSideIsWinning(uint256 _pledgeAmount) public {
    _pledgeAmount = bound(_pledgeAmount, 1, type(uint192).max);

    // Making the against percentage 60% of the total as percentageDiff is 20%
    // Note: I'm using 301 to account for rounding down errors. I'm also setting some _pledgesFor
    //       to avoid the case when pledges are at 0 and someone just pledges 1 token
    //       which is not realistic due to the pledgeThreshold forbidding the lines tested here
    //       to be reached.
    uint256 _pledgesFor = 100_000;
    uint256 _pledgesAgainst = (_pledgeAmount + _pledgesFor) * 301 / 200;

    // Set the data
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, _startTime, _pledgesFor, _pledgesAgainst
    );
    module.forTest_setInequalityData(
      _disputeId, IBondEscalationResolutionModule.InequalityStatus.ForTurnToEqualize, block.timestamp
    );

    // Mock and expect IBondEscalationAccounting.pledge to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IBondEscalationAccounting.pledge, (pledgerFor, _requestId, _disputeId, token, _pledgeAmount)),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit PledgedForDispute(pledgerFor, _requestId, _disputeId, _pledgeAmount);

    vm.prank(pledgerFor);
    module.pledgeForDispute(mockRequest, mockDispute, _pledgeAmount);

    (,, uint256 _realPledgesFor,) = module.escalations(_disputeId);
    (IBondEscalationResolutionModule.InequalityStatus _status, uint256 _timer) = module.inequalityData(_disputeId);

    // Check: is the pledge amount added to the total?
    assertEq(_realPledgesFor, _pledgesFor + _pledgeAmount);
    // Check: is the pledges for amount updated?
    assertEq(module.pledgesForDispute(_disputeId, pledgerFor), _pledgeAmount);
    // Check: is the status properly updated?
    assertEq(uint256(_status), uint256(IBondEscalationResolutionModule.InequalityStatus.ForTurnToEqualize));
    // Check: is the timer properly updated to current timestamp?
    assertEq(uint256(_timer), block.timestamp);
  }

  /**
   * @notice Testing _status == forTurnToEqualize && both diffs < percentageDiff
   */
  function test_changesStatusIfSidesAreEqual(uint256 _pledgeAmount) public {
    _pledgeAmount = bound(_pledgeAmount, 1, type(uint192).max);

    // Making both the same so the percentage diff is not reached
    uint256 _pledgesFor = 100_000;
    uint256 _pledgesAgainst = (_pledgeAmount + _pledgesFor);

    // Resetting the pledges values
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, _startTime, _pledgesFor, _pledgesAgainst
    );

    module.forTest_setInequalityData(
      _disputeId, IBondEscalationResolutionModule.InequalityStatus.ForTurnToEqualize, block.timestamp
    );

    // Mock and expect IBondEscalationAccounting.pledge to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IBondEscalationAccounting.pledge, (pledgerFor, _requestId, _disputeId, token, _pledgeAmount)),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit PledgedForDispute(pledgerFor, _requestId, _disputeId, _pledgeAmount);

    vm.prank(pledgerFor);
    module.pledgeForDispute(mockRequest, mockDispute, _pledgeAmount);

    (,, uint256 _realPledgesFor,) = module.escalations(_disputeId);
    (IBondEscalationResolutionModule.InequalityStatus _status, uint256 _timer) = module.inequalityData(_disputeId);

    // Check: is the pledge amount added to the total?
    assertEq(_realPledgesFor, _pledgesFor + _pledgeAmount);
    // Check: is the pledges for amount updated?
    assertEq(module.pledgesForDispute(_disputeId, pledgerFor), _pledgeAmount);
    // Check: is the status properly updated?
    assertEq(uint256(_status), uint256(IBondEscalationResolutionModule.InequalityStatus.Equalized));
    // Check: is the timer reset?
    assertEq(_timer, 0);
  }
}

contract BondEscalationResolutionModule_Unit_PledgeAgainstDispute is BaseTest {
  uint128 internal _startTime;
  bytes32 internal _disputeId;
  bytes32 internal _requestId;

  function setUp() public override {
    super.setUp();

    // Start at a later time to be able to travel back
    vm.warp(block.timestamp + timeToBreakInequality + 1);

    // block.timestamp < _startTime + _timeUntilDeadline
    _startTime = uint128(block.timestamp - timeUntilDeadline + 1);

    (_requestId,, _disputeId) = _setResolutionModuleData(requestParameters);
  }

  function test_reverts(
    uint256 _pledgeAmount,
    IBondEscalationResolutionModule.RequestParameters memory _params
  ) public assumeFuzzable(address(_params.accountingExtension)) {
    // 1. BondEscalationResolutionModule_NotEscalated
    (_requestId,, _disputeId) = _setResolutionModuleData(_params);

    // Set mock escalation with no pledges and start time 0
    module.forTest_setEscalation(_disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, 0, 0, 0);

    // Check: does it revert if the dispute is not escalated?
    vm.expectRevert(IBondEscalationResolutionModule.BondEscalationResolutionModule_NotEscalated.selector);
    module.pledgeAgainstDispute(mockRequest, mockDispute, _pledgeAmount);

    // 2. BondEscalationResolutionModule_PledgingPhaseOver
    _params.timeUntilDeadline = block.timestamp - 1;
    (_requestId,, _disputeId) = _setResolutionModuleData(_params);
    // Set mock escalation with no pledges and start time 1
    module.forTest_setEscalation(_disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, 1, 0, 0);

    // Check: does it revert if the pledging phase is over?
    vm.expectRevert(IBondEscalationResolutionModule.BondEscalationResolutionModule_PledgingPhaseOver.selector);
    module.pledgeAgainstDispute(mockRequest, mockDispute, _pledgeAmount);

    // 3. BondEscalationResolutionModule_MustBeResolved
    _params.timeUntilDeadline = 10_000;
    _params.timeToBreakInequality = timeToBreakInequality;

    (_requestId,, _disputeId) = _setResolutionModuleData(_params);

    IBondEscalationResolutionModule.InequalityStatus _inequalityStatus =
      IBondEscalationResolutionModule.InequalityStatus.ForTurnToEqualize;
    module.forTest_setInequalityData(_disputeId, _inequalityStatus, block.timestamp);

    // Set mock escalation with no pledges and start time == block.timestamp
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, uint128(block.timestamp), 0, 0
    );

    vm.warp(block.timestamp + _params.timeToBreakInequality);

    // Check: does it revert if inequality timer has passed?
    vm.expectRevert(IBondEscalationResolutionModule.BondEscalationResolutionModule_MustBeResolved.selector);
    module.pledgeAgainstDispute(mockRequest, mockDispute, _pledgeAmount);

    // 4. BondEscalationResolutionModule_AgainstTurnToEqualize
    vm.warp(block.timestamp - _params.timeToBreakInequality - 1); // Not past the deadline anymore
    module.forTest_setInequalityData(_disputeId, _inequalityStatus, block.timestamp);

    // Mock and expect the pledge call
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        IBondEscalationAccounting.pledge, (pledgerAgainst, _requestId, _disputeId, _params.bondToken, _pledgeAmount)
      ),
      abi.encode()
    );

    // Check: does it revert if status == AgainstTurnToEqualize?
    vm.expectRevert(IBondEscalationResolutionModule.BondEscalationResolutionModule_ForTurnToEqualize.selector);
    vm.prank(pledgerAgainst);
    module.pledgeAgainstDispute(mockRequest, mockDispute, _pledgeAmount);
  }

  function test_earlyReturnIfThresholdNotSurpassed(uint256 _pledgeAmount) public {
    vm.assume(_pledgeAmount < type(uint256).max - 1000);

    // block.timestamp < _startTime + _timeUntilDeadline
    _startTime = uint128(block.timestamp - timeUntilDeadline + 1);

    // _pledgeThreshold > _updatedTotalVotes;
    uint256 _pledgesFor = 1000;
    uint256 _pledgesAgainst = 1000;
    requestParameters.pledgeThreshold = _pledgesFor + _pledgesAgainst + _pledgeAmount + 1;

    (_requestId,, _disputeId) = _setResolutionModuleData(requestParameters);

    // Assuming the threshold has not passed, this is the only valid state
    IBondEscalationResolutionModule.InequalityStatus _inequalityStatus =
      IBondEscalationResolutionModule.InequalityStatus.Equalized;

    // Set all data
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, _startTime, _pledgesFor, _pledgesAgainst
    );
    module.forTest_setInequalityData(_disputeId, _inequalityStatus, block.timestamp);

    // Mock and expect IBondEscalationAccounting.pledge to be called
    _mockAndExpect(
      address(requestParameters.accountingExtension),
      abi.encodeCall(
        IBondEscalationAccounting.pledge,
        (pledgerAgainst, _requestId, _disputeId, requestParameters.bondToken, _pledgeAmount)
      ),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit PledgedAgainstDispute(pledgerAgainst, _requestId, _disputeId, _pledgeAmount);

    vm.startPrank(pledgerAgainst);
    module.pledgeAgainstDispute(mockRequest, mockDispute, _pledgeAmount);

    (,,, uint256 _realPledgesAgainst) = module.escalations(_disputeId);
    (IBondEscalationResolutionModule.InequalityStatus _status,) = module.inequalityData(_disputeId);

    // Check: is the pledge amount added to the total?
    assertEq(_realPledgesAgainst, _pledgesAgainst + _pledgeAmount);
    // Check: is the pledges against amount updated?
    assertEq(module.pledgesAgainstDispute(_disputeId, pledgerAgainst), _pledgeAmount);
    // Check: is the status properly updated?
    assertEq(uint256(_status), uint256(IBondEscalationResolutionModule.InequalityStatus.Equalized));
  }

  /**
   * @notice Testing _againstPercentageDifference >= _scaledPercentageDiffAsInt
   */
  function test_changesStatusIfAgainstSideIsWinning(uint256 _pledgeAmount) public {
    _pledgeAmount = bound(_pledgeAmount, 1, type(uint192).max);

    // I'm setting the values so that the percentage diff is 20% in favor of pledgesAgainst.
    // In this case, _pledgeAmount will be the entirety of pledgesAgainst, as if it were the first pledge.
    // Therefore, _pledgeAmount must be 60% of total votes, _pledgesFor then should be 40%
    // 40 = 60 * 2 / 3 -> thats why I'm multiplying by 200 and dividing by 300
    uint256 _pledgesAgainst = 0;
    uint256 _pledgesFor = _pledgeAmount * 200 / 300;

    // Set all data
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, _startTime, _pledgesFor, _pledgesAgainst
    );
    module.forTest_setInequalityData(
      _disputeId, IBondEscalationResolutionModule.InequalityStatus.Equalized, block.timestamp
    );

    // Mock and expect IBondEscalationAccounting.pledge to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IBondEscalationAccounting.pledge, (pledgerAgainst, _requestId, _disputeId, token, _pledgeAmount)),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit PledgedAgainstDispute(pledgerAgainst, _requestId, _disputeId, _pledgeAmount);

    vm.startPrank(pledgerAgainst);
    module.pledgeAgainstDispute(mockRequest, mockDispute, _pledgeAmount);

    (,,, uint256 _realPledgesAgainst) = module.escalations(_disputeId);
    (IBondEscalationResolutionModule.InequalityStatus _status, uint256 _timer) = module.inequalityData(_disputeId);

    // Check: is the pledge amount added to the total?
    assertEq(_realPledgesAgainst, _pledgesAgainst + _pledgeAmount);
    // Check: is the pledges against amount updated?
    assertEq(module.pledgesAgainstDispute(_disputeId, pledgerAgainst), _pledgeAmount);
    // Check: is the status properly updated?
    assertEq(uint256(_status), uint256(IBondEscalationResolutionModule.InequalityStatus.ForTurnToEqualize));
    // Check: is the timer properly updated?
    assertEq(uint256(_timer), block.timestamp);
  }

  /**
   * @notice Testing _forPercentageDifference >= _scaledPercentageDiffAsInt
   */
  function test_changesStatusIfForSideIsWinning(uint256 _pledgeAmount) public {
    _pledgeAmount = bound(_pledgeAmount, 1, type(uint192).max);

    // Making the against percentage 60% of the total as percentageDiff is 20%
    // Note: I'm using 301 to account for rounding down errors. I'm also setting some _pledgesFor
    //       to avoid the case when pledges are at 0 and someone just pledges 1 token
    //       which is not realistic due to the pledgeThreshold forbidding the lines tested here
    //       to be reached.
    uint256 _pledgesAgainst = 100_000;
    uint256 _pledgesFor = (_pledgeAmount + _pledgesAgainst) * 301 / 200;

    // Set the data
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, _startTime, _pledgesFor, _pledgesAgainst
    );
    module.forTest_setInequalityData(
      _disputeId, IBondEscalationResolutionModule.InequalityStatus.AgainstTurnToEqualize, block.timestamp
    );

    // Mock and expect IBondEscalationAccounting.pledge to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IBondEscalationAccounting.pledge, (pledgerAgainst, _requestId, _disputeId, token, _pledgeAmount)),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit PledgedAgainstDispute(pledgerAgainst, _requestId, _disputeId, _pledgeAmount);

    vm.prank(pledgerAgainst);
    module.pledgeAgainstDispute(mockRequest, mockDispute, _pledgeAmount);

    (,,, uint256 _realPledgesAgainst) = module.escalations(_disputeId);
    (IBondEscalationResolutionModule.InequalityStatus _status, uint256 _timer) = module.inequalityData(_disputeId);

    // Check: is the pledge amount added to the total?
    assertEq(_realPledgesAgainst, _pledgesAgainst + _pledgeAmount);
    // Check: is the pledges against amount updated?
    assertEq(module.pledgesAgainstDispute(_disputeId, pledgerAgainst), _pledgeAmount);
    // Check: is the status properly updated?
    assertEq(uint256(_status), uint256(IBondEscalationResolutionModule.InequalityStatus.AgainstTurnToEqualize));
    // // Check: is the timer properly updated?
    assertEq(uint256(_timer), block.timestamp);
  }

  /**
   * @notice Testing _status == againstTurnToEqualize && both diffs < percentageDiff
   */
  function test_changesStatusIfSidesAreEqual(uint256 _pledgeAmount) public {
    _pledgeAmount = bound(_pledgeAmount, 1, type(uint192).max);

    // Making both the same so the percentage diff is not reached
    uint256 _pledgesAgainst = 100_000;
    uint256 _pledgesFor = (_pledgeAmount + _pledgesAgainst);

    // Resetting the pledges values
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, _startTime, _pledgesFor, _pledgesAgainst
    );

    module.forTest_setInequalityData(
      _disputeId, IBondEscalationResolutionModule.InequalityStatus.AgainstTurnToEqualize, block.timestamp
    );

    // Mock and expect IBondEscalationAccounting.pledge to be called
    _mockAndExpect(
      address(accounting),
      abi.encodeCall(IBondEscalationAccounting.pledge, (pledgerAgainst, _requestId, _disputeId, token, _pledgeAmount)),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit PledgedAgainstDispute(pledgerAgainst, _requestId, _disputeId, _pledgeAmount);

    vm.prank(pledgerAgainst);
    module.pledgeAgainstDispute(mockRequest, mockDispute, _pledgeAmount);

    (,, uint256 _realPledgesAgainst,) = module.escalations(_disputeId);
    (IBondEscalationResolutionModule.InequalityStatus _status, uint256 _timer) = module.inequalityData(_disputeId);

    // Check: is the pledge amount added to the total?
    assertEq(_realPledgesAgainst, _pledgesAgainst + _pledgeAmount);
    // Check: is the pledges against amount updated?
    assertEq(module.pledgesAgainstDispute(_disputeId, pledgerAgainst), _pledgeAmount);
    // Check: is the status properly updated?
    assertEq(uint256(_status), uint256(IBondEscalationResolutionModule.InequalityStatus.Equalized));
    // Check: is the timer properly reset?
    assertEq(_timer, 0);
  }
}

contract BondEscalationResolutionModule_Unit_ResolveDispute is BaseTest {
  /*
  Specs:
    0. Should revert if the resolution status is different than Unresolved - done
    1. Should revert if the dispute is not escalated (startTime == 0) - done
    2. Should revert if the main deadline has not be reached and the inequality timer has not culminated - done

    3. After resolve, if the pledges from both sides never reached the threshold, or if the pledges of both sides end up tied
       it should set the resolution status to NoResolution.
    4. After resolve, if the pledges for the disputer were more than the pledges against him, then it should
       set the resolution state to DisputerWon and call the oracle to update the status with Won. Also emit event.
    5. Same as 4 but with DisputerLost, and Lost when the pledges against the disputer were more than the pledges in favor of
       the disputer.
  */

  function test_reverts(IBondEscalationResolutionModule.RequestParameters memory _params)
    public
    assumeFuzzable(address(_params.accountingExtension))
  {
    // 1. BondEscalationResolutionModule_AlreadyResolved
    (bytes32 _requestId, bytes32 _responseId, bytes32 _disputeId) = _setResolutionModuleData(_params);

    // Set mock escalation with resolution == DisputerWon
    module.forTest_setEscalation(_disputeId, IBondEscalationResolutionModule.Resolution.DisputerWon, 0, 0, 0);

    // Check: does it revert if the status is different than resolved?
    vm.expectRevert(IBondEscalationResolutionModule.BondEscalationResolutionModule_AlreadyResolved.selector);

    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);

    // 2. BondEscalationResolutionModule_NotEscalated
    _params.timeUntilDeadline = 100_000;
    _params.timeToBreakInequality = 100_000;

    (_requestId, _responseId, _disputeId) = _setResolutionModuleData(_params);

    // Set mock escalation with resolution == Unresolved
    module.forTest_setEscalation(_disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, 0, 0, 0);

    // Check: does it revert if the dispute is not escalated?
    vm.expectRevert(IBondEscalationResolutionModule.BondEscalationResolutionModule_NotEscalated.selector);

    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);

    // 3. BondEscalationResolutionModule_PledgingPhaseNotOver
    IBondEscalationResolutionModule.InequalityStatus _inequalityStatus =
      IBondEscalationResolutionModule.InequalityStatus.AgainstTurnToEqualize;
    module.forTest_setInequalityData(_disputeId, _inequalityStatus, block.timestamp);

    // Set mock escalation with resolution == Unresolved and start time == block.timestamp
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, uint128(block.timestamp), 0, 0
    );

    // Check: does it revert if the dispute must be resolved?
    vm.expectRevert(IBondEscalationResolutionModule.BondEscalationResolutionModule_PledgingPhaseNotOver.selector);

    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);
  }

  function test_thresholdNotReached() public {
    // START OF SETUP TO AVOID REVERTS
    (bytes32 _requestId,, bytes32 _disputeId) = _setResolutionModuleData(requestParameters);

    // Set a mock escalation with resolution == Unresolved and start time == 1
    module.forTest_setEscalation(_disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, 1, 0, 0);

    // Mock and expect IOracle.updateDisputeStatus to be called
    _mockAndExpect(
      address(oracle),
      abi.encodeCall(
        IOracle.updateDisputeStatus, (mockRequest, mockResponse, mockDispute, IOracle.DisputeStatus.NoResolution)
      ),
      abi.encode()
    );
    // END OF SETUP TO AVOID REVERTS

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit DisputeResolved(_requestId, _disputeId, IOracle.DisputeStatus.NoResolution);

    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);

    (IBondEscalationResolutionModule.Resolution _trueResStatus,,,) = module.escalations(_disputeId);

    // Check: is the resolution status updated to NoResolution?
    assertEq(uint256(_trueResStatus), uint256(IBondEscalationResolutionModule.Resolution.NoResolution));
  }

  function test_tiedPledges() public {
    // START OF SETUP TO AVOID REVERTS
    (bytes32 _requestId,, bytes32 _disputeId) = _setResolutionModuleData(requestParameters);

    // Set mock escalation with tied pledges
    module.forTest_setEscalation(_disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, 1, 2000, 2000);

    // Mock and expect IOracle.updateDisputeStatus to be called
    _mockAndExpect(
      address(oracle),
      abi.encodeCall(
        IOracle.updateDisputeStatus, (mockRequest, mockResponse, mockDispute, IOracle.DisputeStatus.NoResolution)
      ),
      abi.encode()
    );

    // END OF SETUP TO AVOID REVERTS

    // START OF TIED PLEDGES

    // Events
    vm.expectEmit(true, true, true, true, address(module));
    emit DisputeResolved(_requestId, _disputeId, IOracle.DisputeStatus.NoResolution);

    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);

    (IBondEscalationResolutionModule.Resolution _trueResStatus,,,) = module.escalations(_disputeId);

    // Check: is the escalation status updated to NoResolution?
    assertEq(uint256(_trueResStatus), uint256(IBondEscalationResolutionModule.Resolution.NoResolution));

    // END OF TIED PLEDGES
  }

  function test_forPledgesWon(uint256 _pledgesAgainst, uint256 _pledgesFor) public {
    vm.assume(_pledgesAgainst < _pledgesFor);
    vm.assume(_pledgesFor < type(uint128).max);
    // START OF SETUP TO AVOID REVERTS
    (bytes32 _requestId,, bytes32 _disputeId) = _setResolutionModuleData(requestParameters);

    // Set mock escalation with pledgers for dispute winning
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, 1, _pledgesFor, _pledgesAgainst
    );
    // END OF SETUP TO AVOID REVERTS

    // START OF FOR PLEDGES WON

    // Mock and expect IOracle.updateDisputeStatus to be called
    _mockAndExpect(
      address(oracle),
      abi.encodeCall(IOracle.updateDisputeStatus, (mockRequest, mockResponse, mockDispute, IOracle.DisputeStatus.Won)),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit DisputeResolved(_requestId, _disputeId, IOracle.DisputeStatus.Won);

    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);

    (IBondEscalationResolutionModule.Resolution _trueResStatus,,,) = module.escalations(_disputeId);
    // Check: is the status of the escalation == DisputerWon?
    assertEq(uint256(_trueResStatus), uint256(IBondEscalationResolutionModule.Resolution.DisputerWon));

    // END OF FOR PLEDGES WON
  }

  function test_againstPledgesWon(uint256 _pledgesFor, uint256 _pledgesAgainst) public {
    vm.assume(_pledgesAgainst > _pledgesFor);
    vm.assume(_pledgesAgainst < type(uint128).max);

    // START OF SETUP TO AVOID REVERTS
    (bytes32 _requestId,, bytes32 _disputeId) = _setResolutionModuleData(requestParameters);

    // Set mock escalation with pledgers against dispute winning
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, 1, _pledgesFor, _pledgesAgainst
    );
    // END OF SETUP TO AVOID REVERTS

    // START OF FOR PLEDGES LOST

    // Mock and expect IOracle.updateDisputeStatus to be called
    _mockAndExpect(
      address(oracle),
      abi.encodeCall(IOracle.updateDisputeStatus, (mockRequest, mockResponse, mockDispute, IOracle.DisputeStatus.Lost)),
      abi.encode()
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit DisputeResolved(_requestId, _disputeId, IOracle.DisputeStatus.Lost);

    vm.prank(address(oracle));
    module.resolveDispute(_disputeId, mockRequest, mockResponse, mockDispute);

    (IBondEscalationResolutionModule.Resolution _trueResStatus,,,) = module.escalations(_disputeId);
    // Check: is the status of the escalation == DisputerLost?
    assertEq(uint256(_trueResStatus), uint256(IBondEscalationResolutionModule.Resolution.DisputerLost));

    // END OF FOR PLEDGES LOST
  }
}

contract BondEscalationResolutionModule_Unit_ClaimPledge is BaseTest {
  function test_reverts(
    bytes32 _disputeId,
    uint256 _pledgesFor,
    uint256 _pledgesAgainst,
    uint128 _startTime,
    address _randomPledger,
    IOracle.Request calldata _request
  ) public {
    // Set a mock escalation with resolution == Unresolved
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.Unresolved, _startTime, _pledgesFor, _pledgesAgainst
    );

    module.forTest_setPledgesFor(_disputeId, _randomPledger, _pledgesFor);
    module.forTest_setPledgesAgainst(_disputeId, _randomPledger, _pledgesAgainst);

    // Check: does it revert if trying to claim a pledge of a not resolved escalation?
    vm.expectRevert(IBondEscalationResolutionModule.BondEscalationResolutionModule_NotResolved.selector);
    module.claimPledge(_request, mockDispute);
  }

  function test_disputerWon(
    uint256 _totalPledgesFor,
    uint256 _totalPledgesAgainst,
    uint256 _userForPledge,
    address _randomPledger,
    IBondEscalationResolutionModule.RequestParameters memory _params
  ) public assumeFuzzable(address(_params.accountingExtension)) {
    // Im bounding to type(uint192).max because it has 58 digits and base has 18, so multiplying results in
    // 77 digits, which is slightly less than uint256 max, which has 78 digits. Seems fair? Unless it's a very stupid token
    // no single pledger should surpass a balance of type(uint192).max
    _userForPledge = bound(_userForPledge, 0, type(uint192).max);
    vm.assume(_totalPledgesFor > _totalPledgesAgainst);
    vm.assume(_totalPledgesFor >= _userForPledge);

    (bytes32 _requestId,, bytes32 _disputeId) = _setResolutionModuleData(_params);

    // Set mock escalation with resolution == DisputerWon
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.DisputerWon, 0, _totalPledgesFor, _totalPledgesAgainst
    );

    module.forTest_setPledgesFor(_disputeId, _randomPledger, _userForPledge);

    uint256 _pledgerProportion = FixedPointMathLib.mulDivDown(_userForPledge, module.BASE(), (_totalPledgesFor));
    uint256 _amountToRelease =
      _userForPledge + (FixedPointMathLib.mulDivDown(_totalPledgesAgainst, _pledgerProportion, (module.BASE())));

    // Mock and expect IBondEscalationAccounting.releasePledge to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        accounting.releasePledge, (_requestId, _disputeId, _randomPledger, _params.bondToken, _amountToRelease)
      ),
      abi.encode(true)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit PledgeClaimed(
      _requestId,
      _disputeId,
      _randomPledger,
      _params.bondToken,
      _amountToRelease,
      IBondEscalationResolutionModule.Resolution.DisputerWon
    );

    vm.prank(_randomPledger);
    module.claimPledge(mockRequest, mockDispute);

    // Check: are the pledges for dispute for the dispute and pledger set to 0?
    assertEq(module.pledgesForDispute(_disputeId, _randomPledger), 0);
  }

  function test_disputerLost(
    uint256 _totalPledgesFor,
    uint256 _totalPledgesAgainst,
    uint256 _userAgainstPledge,
    address _randomPledger,
    IBondEscalationResolutionModule.RequestParameters memory _params
  ) public assumeFuzzable(address(_params.accountingExtension)) {
    // Im bounding to type(uint192).max because it has 58 digits and base has 18, so multiplying results in
    // 77 digits, which is slightly less than uint256 max, which has 78 digits. Seems fair? Unless it's a very stupid token
    // no single pledger should surpass a balance of type(uint192).max
    _userAgainstPledge = bound(_userAgainstPledge, 0, type(uint192).max);
    vm.assume(_totalPledgesAgainst > _totalPledgesFor);
    vm.assume(_totalPledgesAgainst >= _userAgainstPledge);

    (bytes32 _requestId,, bytes32 _disputeId) = _setResolutionModuleData(_params);

    // Set mock escalation with resolution == DisputerLost
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.DisputerLost, 0, _totalPledgesFor, _totalPledgesAgainst
    );

    module.forTest_setPledgesAgainst(_disputeId, _randomPledger, _userAgainstPledge);

    uint256 _pledgerProportion = FixedPointMathLib.mulDivDown(_userAgainstPledge, module.BASE(), _totalPledgesAgainst);
    uint256 _amountToRelease =
      _userAgainstPledge + (FixedPointMathLib.mulDivDown(_totalPledgesFor, _pledgerProportion, module.BASE()));

    // Mock and expect IBondEscalationAccounting.releasePledge to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        accounting.releasePledge, (_requestId, _disputeId, _randomPledger, _params.bondToken, _amountToRelease)
      ),
      abi.encode(true)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit PledgeClaimed(
      _requestId,
      _disputeId,
      _randomPledger,
      _params.bondToken,
      _amountToRelease,
      IBondEscalationResolutionModule.Resolution.DisputerLost
    );

    vm.prank(_randomPledger);
    module.claimPledge(mockRequest, mockDispute);

    // Check: is the pledges against dispute for this dispute and pledger set to 0?
    assertEq(module.pledgesAgainstDispute(_disputeId, _randomPledger), 0);
  }

  function test_noResolution(
    uint256 _userForPledge,
    uint256 _userAgainstPledge,
    address _randomPledger,
    IBondEscalationResolutionModule.RequestParameters memory _params
  ) public assumeFuzzable(address(_params.accountingExtension)) {
    vm.assume(_userForPledge > 0);
    vm.assume(_userAgainstPledge > 0);

    (bytes32 _requestId,, bytes32 _disputeId) = _setResolutionModuleData(_params);

    // Set mock escalation with resolution == NoResolution
    module.forTest_setEscalation(
      _disputeId, IBondEscalationResolutionModule.Resolution.NoResolution, 0, _userForPledge, _userAgainstPledge
    );

    module.forTest_setPledgesFor(_disputeId, _randomPledger, _userForPledge);
    module.forTest_setPledgesAgainst(_disputeId, _randomPledger, _userAgainstPledge);

    // Mock and expect IBondEscalationAccounting.releasePledge to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        accounting.releasePledge, (_requestId, _disputeId, _randomPledger, _params.bondToken, _userForPledge)
      ),
      abi.encode(true)
    );

    // Mock and expect IBondEscalationAccounting.releasePledge to be called
    _mockAndExpect(
      address(_params.accountingExtension),
      abi.encodeCall(
        accounting.releasePledge, (_requestId, _disputeId, _randomPledger, _params.bondToken, _userAgainstPledge)
      ),
      abi.encode(true)
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit PledgeClaimed(
      _requestId,
      _disputeId,
      _randomPledger,
      _params.bondToken,
      _userForPledge,
      IBondEscalationResolutionModule.Resolution.NoResolution
    );

    // Check: is the event emitted?
    vm.expectEmit(true, true, true, true, address(module));
    emit PledgeClaimed(
      _requestId,
      _disputeId,
      _randomPledger,
      _params.bondToken,
      _userAgainstPledge,
      IBondEscalationResolutionModule.Resolution.NoResolution
    );

    vm.prank(_randomPledger);
    module.claimPledge(mockRequest, mockDispute);

    // Check: is the pledges against dispute for this dispute and pledger set to 0?
    assertEq(module.pledgesAgainstDispute(_disputeId, _randomPledger), 0);
    // Check: is the pledges for dispute for this dispute and pledger set to 0?
    assertEq(module.pledgesForDispute(_disputeId, _randomPledger), 0);
  }
}
