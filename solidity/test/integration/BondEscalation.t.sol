// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import './IntegrationBase.sol';

// contract Integration_BondEscalation is IntegrationBase {
//   bytes internal _responseData = abi.encode('response');
//   bytes32 internal _requestId;
//   bytes32 internal _responseId;
//   bytes32 internal _disputeId;
//   uint256 internal _bondEscalationDeadline;
//   uint256 internal _tyingBuffer = 1 days;
//   uint256 internal _disputeWindow = 3 days;
//   // TODO: There is a bug in the accounting, try with pledge size = 1 ether
//   // uint256 internal _pledgeSize = 5 ether;
//   uint256 internal _pledgeSize = _expectedBondSize;

//   function setUp() public override {
//     super.setUp();
//     _expectedDeadline = block.timestamp + 10 days;
//     _bondEscalationDeadline = block.timestamp + 5 days;

//     IOracle.NewRequest memory _request = IOracle.NewRequest({
//       requestModuleData: abi.encode(
//         IHttpRequestModule.RequestParameters({
//           url: _expectedUrl,
//           method: _expectedMethod,
//           body: _expectedBody,
//           accountingExtension: _bondEscalationAccounting,
//           paymentToken: usdc,
//           paymentAmount: _expectedReward
//         })
//         ),
//       responseModuleData: abi.encode(
//         IBondedResponseModule.RequestParameters({
//           accountingExtension: _bondEscalationAccounting,
//           bondToken: usdc,
//           bondSize: _expectedBondSize,
//           deadline: _expectedDeadline,
//           disputeWindow: _baseDisputeWindow
//         })
//         ),
//       disputeModuleData: abi.encode(
//         IBondEscalationModule.RequestParameters({
//           accountingExtension: _bondEscalationAccounting,
//           bondToken: usdc,
//           bondSize: _pledgeSize,
//           maxNumberOfEscalations: 10,
//           bondEscalationDeadline: _bondEscalationDeadline,
//           tyingBuffer: _tyingBuffer,
//           disputeWindow: _disputeWindow
//         })
//         ),
//       resolutionModuleData: abi.encode(_mockArbitrator),
//       finalityModuleData: abi.encode(
//         ICallbackModule.RequestParameters({target: address(_mockCallback), data: abi.encode(_expectedCallbackValue)})
//         ),
//       requestModule: _requestModule,
//       responseModule: _responseModule,
//       disputeModule: _bondEscalationModule,
//       resolutionModule: _arbitratorModule,
//       finalityModule: IFinalityModule(_callbackModule),
//       ipfsHash: _ipfsHash
//     });

//     // Requester creates a request
//     _forBondDepositERC20(_bondEscalationAccounting, requester, usdc, _expectedReward, _expectedReward);
//     vm.startPrank(requester);
//     _bondEscalationAccounting.approveModule(address(_requestModule));
//     _requestId = oracle.createRequest(_request);
//     vm.stopPrank();

//     // Proposer proposes a response
//     _forBondDepositERC20(_bondEscalationAccounting, proposer, usdc, _expectedBondSize, _expectedBondSize);
//     vm.startPrank(proposer);
//     _bondEscalationAccounting.approveModule(address(_responseModule));
//     _responseId = oracle.proposeResponse(_requestId, _responseData);
//     vm.stopPrank();

//     // Disputer disputes the response
//     _forBondDepositERC20(_bondEscalationAccounting, disputer, usdc, _expectedBondSize, _expectedBondSize);
//     vm.startPrank(disputer);
//     _bondEscalationAccounting.approveModule(address(_bondEscalationModule));
//     _disputeId = oracle.disputeResponse(_requestId, _responseId);
//     vm.stopPrank();
//   }

//   function test_proposerWins() public {
//     // Step 1: Proposer pledges against the dispute
//     _forBondDepositERC20(_bondEscalationAccounting, proposer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(proposer);
//     _bondEscalationAccounting.approveModule(address(_bondEscalationModule));
//     _bondEscalationModule.pledgeAgainstDispute(_disputeId);
//     vm.stopPrank();

//     // Step 2: Disputer doubles down
//     _forBondDepositERC20(_bondEscalationAccounting, disputer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(disputer);
//     _bondEscalationModule.pledgeForDispute(_disputeId);
//     vm.stopPrank();

//     // Step 3: Proposer doubles down
//     _forBondDepositERC20(_bondEscalationAccounting, proposer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(proposer);
//     _bondEscalationModule.pledgeAgainstDispute(_disputeId);
//     vm.stopPrank();

//     // Step 4: Disputer runs out of capital
//     // Step 5: External parties see that Disputer's dispute was wrong so they don't join to escalate
//     // Step 6: Proposer response's is deemed correct and final once the bond escalation window is over
//     vm.warp(_expectedDeadline + _tyingBuffer + 1);
//     _bondEscalationModule.settleBondEscalation(_requestId);

//     IOracle.Dispute memory _dispute = oracle.getDispute(_disputeId);
//     assertEq(uint256(_dispute.status), uint256(IOracle.DisputeStatus.Lost), 'Mismatch: Dispute status');

//     // Step 7: Participants claim the rewards
//     // Test: The requester has not participated in pledging, claiming shouldn't change his balance
//     _bondEscalationAccounting.claimEscalationReward(_disputeId, requester);
//     assertEq(_bondEscalationAccounting.balanceOf(requester, usdc), 0, 'Mismatch: Requester balance');

//     // Test: The proposer receives 2x pledging amount + disputer's bond + disputer's pledge
//     _bondEscalationAccounting.claimEscalationReward(_disputeId, proposer);
//     assertEq(
//       _bondEscalationAccounting.balanceOf(proposer, usdc),
//       _pledgeSize * 3 + _expectedBondSize,
//       'Mismatch: Proposer balance'
//     );

//     // Test: The disputer has lost his pledge
//     _bondEscalationAccounting.claimEscalationReward(_disputeId, disputer);
//     assertEq(_bondEscalationAccounting.balanceOf(disputer, usdc), 0, 'Mismatch: Disputer balance');

//     // Step 8: Finalize request and check balances again
//     oracle.finalize(_requestId, _responseId);

//     // Test: The requester has no balance because he has paid the proposer
//     assertEq(_bondEscalationAccounting.balanceOf(requester, usdc), 0, 'Mismatch: Requester balance');

//     // Test: The proposer receives the requester's reward for proposing a correct response and his bond back
//     assertEq(
//       _bondEscalationAccounting.balanceOf(proposer, usdc),
//       _pledgeSize * 3 + _expectedBondSize * 2 + _expectedReward,
//       'Mismatch: Proposer balance'
//     );

//     // Test: The disputer's balance has not changed
//     assertEq(_bondEscalationAccounting.balanceOf(disputer, usdc), 0, 'Mismatch: Disputer balance');
//   }

//   function test_proposerLoses() public {
//     // Step 1: Proposer pledges against the dispute
//     _forBondDepositERC20(_bondEscalationAccounting, proposer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(proposer);
//     _bondEscalationAccounting.approveModule(address(_bondEscalationModule));
//     _bondEscalationModule.pledgeAgainstDispute(_disputeId);
//     vm.stopPrank();

//     // Step 2: Disputer doubles down
//     _forBondDepositERC20(_bondEscalationAccounting, disputer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(disputer);
//     _bondEscalationModule.pledgeForDispute(_disputeId);
//     vm.stopPrank();

//     // Step 3: Another party joins the dispute
//     address _secondDisputer = makeAddr('secondDisputer');
//     _forBondDepositERC20(_bondEscalationAccounting, _secondDisputer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(_secondDisputer);
//     _bondEscalationModule.pledgeForDispute(_disputeId);
//     vm.stopPrank();

//     // Step 4: Proposer runs out of capital and doesn't pledge anymore
//     // External parties see that Proposer's proposal was wrong so they don't join to escalate

//     // Step 5: Proposer response's is deemed incorrect. The bond escalation process along with the tying buffer is terminated
//     vm.warp(_bondEscalationDeadline + _tyingBuffer + 1);
//     _bondEscalationModule.settleBondEscalation(_requestId);

//     IOracle.Dispute memory _dispute = oracle.getDispute(_disputeId);
//     assertEq(uint256(_dispute.status), uint256(IOracle.DisputeStatus.Won), 'Mismatch: Dispute status');

//     // Step 6: Participants claim the rewards
//     // Test: The requester has not participated in pledging, claiming shouldn't change his balance
//     _bondEscalationAccounting.claimEscalationReward(_disputeId, requester);
//     assertEq(_bondEscalationAccounting.balanceOf(requester, usdc), 0, 'Mismatch: Requester balance');

//     // Test: The proposer has lost his pledge
//     _bondEscalationAccounting.claimEscalationReward(_disputeId, proposer);
//     assertEq(_bondEscalationAccounting.balanceOf(proposer, usdc), 0, 'Mismatch: Proposer balance');

//     // Test: The disputer has received his pledge and bond back, a half of the proposer's pledge and the proposer's bond
//     _bondEscalationAccounting.claimEscalationReward(_disputeId, disputer);
//     assertEq(
//       _bondEscalationAccounting.balanceOf(disputer, usdc),
//       _pledgeSize + _pledgeSize / 2 + _expectedBondSize * 2,
//       'Mismatch: Disputer balance'
//     );

//     // Test: The second disputer has received his pledge back and a half of the proposer's pledge
//     _bondEscalationAccounting.claimEscalationReward(_disputeId, _secondDisputer);
//     assertEq(
//       _bondEscalationAccounting.balanceOf(_secondDisputer, usdc),
//       _pledgeSize + _pledgeSize / 2,
//       'Mismatch: Second Disputer balance'
//     );

//     // Step 7: Other parties can now propose different answers. Another proposer proposes a new answer
//     address _anotherProposer = makeAddr('anotherProposer');
//     _forBondDepositERC20(_bondEscalationAccounting, _anotherProposer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(_anotherProposer);
//     _bondEscalationAccounting.approveModule(address(_responseModule));
//     _responseId = oracle.proposeResponse(_requestId, abi.encode('anotherResponse'));
//     vm.stopPrank();

//     // Step 8: Disputer disputes Another proposer's answer
//     // _forBondDepositERC20(_bondEscalationAccounting, disputer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(disputer);
//     _bondEscalationAccounting.approveModule(address(_bondEscalationModule));
//     _disputeId = oracle.disputeResponse(_requestId, _responseId);
//     vm.stopPrank();

//     // Step 9: Shouldn't be able to pledge for or against the dispute due to the bond escalation deadline being over
//     _forBondDepositERC20(_bondEscalationAccounting, disputer, usdc, _pledgeSize, _pledgeSize);
//     vm.expectRevert(IBondEscalationModule.BondEscalationModule_InvalidDispute.selector);
//     vm.startPrank(disputer);
//     _bondEscalationModule.pledgeForDispute(_disputeId);
//     vm.stopPrank();

//     // Step 10: The dispute goes to the resolution module
//     oracle.escalateDispute(_disputeId);
//     _dispute = oracle.getDispute(_disputeId);
//     assertEq(uint256(_dispute.status), uint256(IOracle.DisputeStatus.Escalated), 'Mismatch: Dispute status');

//     // Step 11: Because Another proposer's answer is disputed, a third party can propose a new answer
//     address _thirdProposer = makeAddr('thirdProposer');
//     _forBondDepositERC20(_bondEscalationAccounting, _thirdProposer, usdc, _expectedBondSize, _expectedBondSize);
//     vm.startPrank(_thirdProposer);
//     _bondEscalationAccounting.approveModule(address(_responseModule));
//     _responseId = oracle.proposeResponse(_requestId, abi.encode('thirdResponse'));
//     vm.stopPrank();

//     // Step 12: It goes undisputed for three days, therefore it's deemed correct and final
//     vm.warp(_expectedDeadline + 1);
//     oracle.finalize(_requestId, _responseId);

//     // Test: The requester has paid out the reward
//     assertEq(_bondEscalationAccounting.balanceOf(requester, usdc), 0, 'Mismatch: Requester balance');

//     // Test: The first proposer has received nothing
//     assertEq(_bondEscalationAccounting.balanceOf(proposer, usdc), 0, 'Mismatch: Proposer balance');

//     // Test: The second proposer has received nothing
//     assertEq(_bondEscalationAccounting.balanceOf(_anotherProposer, usdc), 0, 'Mismatch: Another Proposer balance');

//     // Test: The third proposer has received the reward and this bond
//     assertEq(
//       _bondEscalationAccounting.balanceOf(_thirdProposer, usdc),
//       _expectedReward + _expectedBondSize,
//       'Mismatch: Third Proposer balance'
//     );

//     // Test: The disputer has received his pledge and bond back, a half of the proposer's pledge and the proposer's bond
//     assertEq(
//       _bondEscalationAccounting.balanceOf(disputer, usdc),
//       _pledgeSize + _pledgeSize / 2 + _expectedBondSize * 2,
//       'Mismatch: Disputer balance'
//     );

//     // Test: The second disputer has not participated in a new dispute, his balance is the same
//     assertEq(
//       _bondEscalationAccounting.balanceOf(_secondDisputer, usdc),
//       _pledgeSize + _pledgeSize / 2,
//       'Mismatch: Second Disputer balance'
//     );

//     // Step 13: Two days after the deadline, the resolution module says that Another proposer's answer was correct
//     // So Another proposer gets paid Disputer's bond
//     vm.warp(_expectedDeadline + 2 days);
//     _mockArbitrator.setAnswer(IOracle.DisputeStatus.Lost);
//     oracle.resolveDispute(_disputeId);

//     // Test: The requester still has nothing
//     assertEq(_bondEscalationAccounting.balanceOf(requester, usdc), 0, 'Mismatch: Requester balance');

//     // Test: The first proposer still has nothing
//     assertEq(_bondEscalationAccounting.balanceOf(proposer, usdc), 0, 'Mismatch: Proposer balance');

//     // Test: The second proposer has received the Disputer's bond
//     assertEq(
//       _bondEscalationAccounting.balanceOf(_anotherProposer, usdc),
//       _expectedBondSize,
//       'Mismatch: Another Proposer balance'
//     );

//     // Test: The third proposer has not done anything
//     assertEq(
//       _bondEscalationAccounting.balanceOf(_thirdProposer, usdc),
//       _expectedReward + _expectedBondSize,
//       'Mismatch: Third Proposer balance'
//     );

//     // Test: The disputer has lost a bond
//     assertEq(
//       _bondEscalationAccounting.balanceOf(disputer, usdc),
//       _pledgeSize + _pledgeSize / 2 + _expectedBondSize * 2,
//       'Mismatch: Disputer balance'
//     );

//     // Test: The second disputer has not has not done anything
//     assertEq(
//       _bondEscalationAccounting.balanceOf(_secondDisputer, usdc),
//       _pledgeSize + _pledgeSize / 2,
//       'Mismatch: Second Disputer balance'
//     );
//   }

//   function test_bondEscalationTied() public {
//     // Step 1: Proposer pledges against the dispute
//     _forBondDepositERC20(_bondEscalationAccounting, proposer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(proposer);
//     _bondEscalationAccounting.approveModule(address(_bondEscalationModule));
//     _bondEscalationModule.pledgeAgainstDispute(_disputeId);
//     vm.stopPrank();

//     // Step 2: Disputer doubles down
//     _forBondDepositERC20(_bondEscalationAccounting, disputer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(disputer);
//     _bondEscalationModule.pledgeForDispute(_disputeId);
//     vm.stopPrank();

//     // Step 3: Proposer doubles down
//     _forBondDepositERC20(_bondEscalationAccounting, proposer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(proposer);
//     _bondEscalationModule.pledgeAgainstDispute(_disputeId);
//     vm.stopPrank();

//     // Step 4: Disputer runs out of capital
//     // Step 5: The tying buffer kicks in
//     vm.warp(_bondEscalationDeadline + 1);

//     // Step 6: An external party sees that Proposer's response is incorrect, so they bond the required WETH
//     address _secondDisputer = makeAddr('secondDisputer');
//     _forBondDepositERC20(_bondEscalationAccounting, _secondDisputer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(_secondDisputer);
//     _bondEscalationModule.pledgeForDispute(_disputeId);
//     vm.stopPrank();

//     // Step 7: They go into the dispute resolution module
//     oracle.escalateDispute(_disputeId);

//     // Step 8: At this point, new answers can be proposed
//     address _secondProposer = makeAddr('secondProposer');
//     _forBondDepositERC20(_bondEscalationAccounting, _secondProposer, usdc, _expectedBondSize, _expectedBondSize);
//     vm.startPrank(_secondProposer);
//     _bondEscalationAccounting.approveModule(address(_responseModule));
//     _responseId = oracle.proposeResponse(_requestId, _responseData);
//     vm.stopPrank();

//     // Step 9: After some time, the resolution module deems Disputer's dispute as correct
//     _mineBlocks(100);
//     oracle.resolveDispute(_disputeId);
//     IOracle.Dispute memory _dispute = oracle.getDispute(_disputeId);
//     assertEq(uint256(_dispute.status), uint256(IOracle.DisputeStatus.Won), 'Mismatch: Dispute status');

//     // Step 10: Participants claim their rewards
//     // Test: The requester has paid out the reward and is left with no balance
//     _bondEscalationAccounting.claimEscalationReward(_disputeId, requester);
//     assertEq(_bondEscalationAccounting.balanceOf(requester, usdc), 0, 'Mismatch: Requester balance');

//     // Test: The proposer has lost his pledge and bond
//     _bondEscalationAccounting.claimEscalationReward(_disputeId, proposer);
//     assertEq(_bondEscalationAccounting.balanceOf(proposer, usdc), 0, 'Mismatch: Proposer balance');

//     // Test: The second proposer hasn't received the reward yet
//     _bondEscalationAccounting.claimEscalationReward(_disputeId, _secondProposer);
//     assertEq(_bondEscalationAccounting.balanceOf(_secondProposer, usdc), 0, 'Mismatch: Second Proposer balance');
//     assertEq(
//       _bondEscalationAccounting.bondedAmountOf(_secondProposer, usdc, _requestId),
//       _expectedBondSize,
//       'Mismatch: Second Proposer bonded balance'
//     );

//     // Test: The Disputer has received his pledge and bond, the proposer's pledge and the proposer's bond
//     _bondEscalationAccounting.claimEscalationReward(_disputeId, disputer);
//     assertEq(
//       _bondEscalationAccounting.balanceOf(disputer, usdc),
//       _pledgeSize * 2 + _expectedBondSize * 2,
//       'Mismatch: Disputer balance'
//     );

//     // Test: The second disputer has received his pledge and the proposer's pledge
//     _bondEscalationAccounting.claimEscalationReward(_disputeId, _secondDisputer);
//     assertEq(
//       _bondEscalationAccounting.balanceOf(_secondDisputer, usdc), _pledgeSize * 2, 'Mismatch: Second Disputer balance'
//     );
//   }

//   function test_externalParties() public {
//     // Step 1: Proposer pledges against the dispute
//     _forBondDepositERC20(_bondEscalationAccounting, proposer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(proposer);
//     _bondEscalationAccounting.approveModule(address(_bondEscalationModule));
//     _bondEscalationModule.pledgeAgainstDispute(_disputeId);
//     vm.stopPrank();

//     // Step 2: Disputer doesn't have money
//     // Step 3: External actor sees that Proposer's answer was incorrect so they pledge in favor of the dispute
//     address _secondDisputer = makeAddr('secondDisputer');
//     _forBondDepositERC20(_bondEscalationAccounting, _secondDisputer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(_secondDisputer);
//     _bondEscalationModule.pledgeForDispute(_disputeId);
//     vm.stopPrank();

//     // Step 4: Proposer doubles down
//     _forBondDepositERC20(_bondEscalationAccounting, proposer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(proposer);
//     _bondEscalationAccounting.approveModule(address(_bondEscalationModule));
//     _bondEscalationModule.pledgeAgainstDispute(_disputeId);
//     vm.stopPrank();

//     // Step 5: External actor sees that Proposer's answer was incorrect so they pledge in favor of the dispute, tying the bond escalation
//     address _thirdDisputer = makeAddr('thirdDisputer');
//     _forBondDepositERC20(_bondEscalationAccounting, _thirdDisputer, usdc, _pledgeSize, _pledgeSize);
//     vm.startPrank(_thirdDisputer);
//     _bondEscalationModule.pledgeForDispute(_disputeId);
//     vm.stopPrank();

//     // Step 6: Proposer loses in resolution
//     vm.warp(_bondEscalationDeadline + 1);
//     oracle.escalateDispute(_disputeId);
//     oracle.resolveDispute(_disputeId);

//     IOracle.Dispute memory _dispute = oracle.getDispute(_disputeId);
//     assertEq(uint256(_dispute.status), uint256(IOracle.DisputeStatus.Won), 'Mismatch: Dispute status');

//     // Step 7: Participants claim the rewards
//     // Test: The requester has not participated in pledging, claiming shouldn't change his balance
//     _bondEscalationAccounting.claimEscalationReward(_disputeId, requester);
//     assertEq(_bondEscalationAccounting.balanceOf(requester, usdc), 0, 'Mismatch: Requester balance');

//     // Test: Proposer's initial bond goes to Disputer
//     _bondEscalationAccounting.claimEscalationReward(_disputeId, proposer);
//     assertEq(_bondEscalationAccounting.balanceOf(proposer, usdc), 0, 'Mismatch: Proposer balance');

//     // Test: Disputers split the proposer's pledges
//     _bondEscalationAccounting.claimEscalationReward(_disputeId, disputer);
//     assertEq(_bondEscalationAccounting.balanceOf(disputer, usdc), _pledgeSize * 2, 'Mismatch: Disputer balance');

//     _bondEscalationAccounting.claimEscalationReward(_disputeId, _secondDisputer);
//     assertEq(
//       _bondEscalationAccounting.balanceOf(_secondDisputer, usdc), _pledgeSize * 2, 'Mismatch: Second Disputer balance'
//     );

//     _bondEscalationAccounting.claimEscalationReward(_disputeId, _thirdDisputer);
//     assertEq(
//       _bondEscalationAccounting.balanceOf(_thirdDisputer, usdc), _pledgeSize * 2, 'Mismatch: Third Disputer balance'
//     );
//   }
// }
