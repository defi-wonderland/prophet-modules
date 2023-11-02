// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity ^0.8.19;

// import 'forge-std/Test.sol';

// import {Helpers} from '../../../utils/Helpers.sol';

// import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
// import {Module, IModule} from '@defi-wonderland/prophet-core-contracts/solidity/contracts/Module.sol';

// import {
//   SequentialResolutionModule,
//   IResolutionModule,
//   ISequentialResolutionModule
// } from '../../../../contracts/modules/resolution/SequentialResolutionModule.sol';

// contract ForTest_ResolutionModule is Module {
//   string public name;
//   IOracle.DisputeStatus internal _responseStatus;

//   constructor(IOracle _oracle, string memory _name) payable Module(_oracle) {
//     name = _name;
//   }

//   function resolveDispute(bytes32 _disputeId) external {
//     ORACLE.updateDisputeStatus(_disputeId, _responseStatus);
//   }

//   function startResolution(bytes32 _disputeId) external {}

//   function moduleName() external view returns (string memory _moduleName) {
//     return name;
//   }

//   function forTest_setResponseStatus(IOracle.DisputeStatus _status) external {
//     _responseStatus = _status;
//   }
// }

// contract BaseTest is Test, Helpers {
//   SequentialResolutionModule public module;
//   IOracle public oracle;
//   bytes32 public disputeId = bytes32(uint256(1));
//   bytes32 public responseId = bytes32(uint256(2));
//   bytes32 public requestId = bytes32(uint256(3));

//   bytes32 public disputeId2 = bytes32(uint256(4));
//   bytes32 public requestId2 = bytes32(uint256(5));

//   address public proposer = makeAddr('proposer');
//   address public disputer = makeAddr('disputer');
//   bytes public responseData = abi.encode('responseData');

//   ForTest_ResolutionModule public submodule1;
//   ForTest_ResolutionModule public submodule2;
//   ForTest_ResolutionModule public submodule3;
//   IResolutionModule[] public resolutionModules;
//   IResolutionModule[] public resolutionModules2;
//   uint256 public sequenceId;
//   uint256 public sequenceId2;

//   event ResolutionSequenceAdded(uint256 _sequenceId, IResolutionModule[] _modules);

//   function setUp() public {
//     oracle = IOracle(makeAddr('Oracle'));
//     vm.etch(address(oracle), hex'069420');

//     vm.mockCall(
//       address(oracle),
//       abi.encodeWithSelector(IOracle.getDispute.selector, disputeId),
//       abi.encode(
//         IOracle.Dispute(block.timestamp, disputer, proposer, responseId, requestId, IOracle.DisputeStatus.Escalated)
//       )
//     );

//     vm.mockCall(
//       address(oracle),
//       abi.encodeWithSelector(IOracle.getDispute.selector, disputeId2),
//       abi.encode(
//         IOracle.Dispute(block.timestamp, disputer, proposer, responseId, requestId2, IOracle.DisputeStatus.Escalated)
//       )
//     );

//     vm.mockCall(address(oracle), abi.encodeWithSelector(IOracle.updateDisputeStatus.selector), abi.encode());

//     module = new SequentialResolutionModule(oracle);

//     submodule1 = new ForTest_ResolutionModule(module, 'module1');
//     submodule2 = new ForTest_ResolutionModule(module, 'module2');
//     submodule3 = new ForTest_ResolutionModule(module, 'module3');

//     vm.mockCall(address(submodule1), abi.encodeWithSelector(IModule.setupRequest.selector), abi.encode());
//     vm.mockCall(address(submodule2), abi.encodeWithSelector(IModule.setupRequest.selector), abi.encode());
//     vm.mockCall(address(submodule3), abi.encodeWithSelector(IModule.setupRequest.selector), abi.encode());

//     resolutionModules.push(IResolutionModule(address(submodule1)));
//     resolutionModules.push(IResolutionModule(address(submodule2)));
//     resolutionModules.push(IResolutionModule(address(submodule3)));

//     sequenceId = module.addResolutionModuleSequence(resolutionModules);

//     bytes[] memory _submoduleData = new bytes[](3);
//     _submoduleData[0] = abi.encode('submodule1Data');
//     _submoduleData[1] = abi.encode('submodule2Data');
//     _submoduleData[2] = abi.encode('submodule3Data');

//     vm.prank(address(oracle));
//     module.setupRequest(
//       requestId,
//       abi.encode(ISequentialResolutionModule.RequestParameters({sequenceId: sequenceId, submoduleData: _submoduleData}))
//     );

//     resolutionModules2.push(IResolutionModule(address(submodule2)));
//     resolutionModules2.push(IResolutionModule(address(submodule3)));
//     resolutionModules2.push(IResolutionModule(address(submodule1)));

//     sequenceId2 = module.addResolutionModuleSequence(resolutionModules2);

//     vm.prank(address(oracle));
//     module.setupRequest(
//       requestId2,
//       abi.encode(
//         ISequentialResolutionModule.RequestParameters({sequenceId: sequenceId2, submoduleData: _submoduleData})
//       )
//     );
//   }
// }

// /**
//  * @title SequentialResolutionModule Unit tests
//  */
// contract SequentialResolutionModule_Unit_ModuleData is BaseTest {
//   function test_decodeRequestParameters() public {
//     ISequentialResolutionModule.RequestParameters memory _params = module.decodeRequestData(requestId);

//     // Check: are all request parameters properly stored?
//     assertEq(_params.sequenceId, sequenceId);
//     assertEq(_params.submoduleData[0], abi.encode('submodule1Data'));
//     assertEq(_params.submoduleData[1], abi.encode('submodule2Data'));
//     assertEq(_params.submoduleData[2], abi.encode('submodule3Data'));
//   }

//   function test_moduleName() public {
//     assertEq(module.moduleName(), 'SequentialResolutionModule');
//   }
// }

// contract SequentialResolutionModule_Unit_Setup is BaseTest {
//   function test_setupRequestCallsAllSubmodules(bytes32 _requestId) public {
//     bytes memory _submodule1Data = abi.encode('submodule1Data');
//     bytes memory _submodule2Data = abi.encode('submodule2Data');
//     bytes memory _submodule3Data = abi.encode('submodule3Data');

//     bytes[] memory _submoduleData = new bytes[](3);
//     _submoduleData[0] = _submodule1Data;
//     _submoduleData[1] = _submodule2Data;
//     _submoduleData[2] = _submodule3Data;

//     // Check: is the submodule 1 called with the proper data?
//     vm.expectCall(
//       address(submodule1), abi.encodeWithSelector(IModule.setupRequest.selector, _requestId, _submodule1Data)
//     );
//     // Check: is the submodule 2 called with the proper data?
//     vm.expectCall(
//       address(submodule2), abi.encodeWithSelector(IModule.setupRequest.selector, _requestId, _submodule2Data)
//     );
//     // Check: is the submodule 3 called with the proper data?
//     vm.expectCall(
//       address(submodule3), abi.encodeWithSelector(IModule.setupRequest.selector, _requestId, _submodule3Data)
//     );

//     vm.prank(address(oracle));
//     module.setupRequest(
//       _requestId,
//       abi.encode(ISequentialResolutionModule.RequestParameters({sequenceId: sequenceId, submoduleData: _submoduleData}))
//     );
//   }

//   function test_addResolutionModuleSequence(IResolutionModule[] memory _testModules) public {
//     uint256 _beforeSequenceId = module.currentSequenceId();

//     // Check: is the event emitted?
//     vm.expectEmit(true, true, true, true, address(module));
//     emit ResolutionSequenceAdded(_beforeSequenceId + 1, _testModules);

//     uint256 _afterSequenceId = module.addResolutionModuleSequence(_testModules);
//     // Check: is the sequence id updated?
//     assertEq(_beforeSequenceId + 1, _afterSequenceId);
//   }

//   function test_setupRequestRevertsIfNotOracle() public {
//     // Check: does it revert if not called by the Oracle?
//     vm.expectRevert(abi.encodeWithSelector(IModule.Module_OnlyOracle.selector));

//     vm.prank(makeAddr('other_sender'));
//     module.setupRequest(requestId, abi.encode());
//   }
// }

// contract SequentialResolutionModule_Unit_OracleProxy is BaseTest {
//   function test_allowedModuleCallsOracle() public {
//     _mockAndExpect(address(oracle), abi.encodeWithSelector(IOracle.allowedModule.selector), abi.encode(true));
//     module.allowedModule(requestId, address(module));
//   }

//   function test_getDisputeCallsOracle() public {
//     IOracle.Dispute memory _dispute;
//     _mockAndExpect(address(oracle), abi.encodeWithSelector(IOracle.getDispute.selector), abi.encode(_dispute));
//     module.getDispute(disputeId);
//   }

//   function test_getResponseCallsOracle() public {
//     IOracle.Response memory _response;
//     _mockAndExpect(address(oracle), abi.encodeWithSelector(IOracle.getResponse.selector), abi.encode(_response));
//     module.getResponse(responseId);
//   }

//   function test_getRequestCallsOracle() public {
//     IOracle.Request memory _request;
//     _mockAndExpect(address(oracle), abi.encodeWithSelector(IOracle.getRequest.selector), abi.encode(_request));
//     module.getRequest(requestId);
//   }

//   function test_getFullRequestCallsOracle() public {
//     IOracle.FullRequest memory _request;
//     _mockAndExpect(address(oracle), abi.encodeWithSelector(IOracle.getFullRequest.selector), abi.encode(_request));
//     module.getFullRequest(requestId);
//   }

//   function test_disputeOfCallsOracle() public {
//     _mockAndExpect(address(oracle), abi.encodeWithSelector(IOracle.disputeOf.selector), abi.encode(disputeId));
//     module.disputeOf(requestId);
//   }

//   function test_getFinalizedResponseCallsOracle() public {
//     IOracle.Response memory _response;
//     _mockAndExpect(
//       address(oracle), abi.encodeWithSelector(IOracle.getFinalizedResponse.selector), abi.encode(_response)
//     );
//     module.getFinalizedResponse(requestId);
//   }

//   function test_getResponseIdsCallsOracle() public {
//     bytes32[] memory _ids;
//     _mockAndExpect(address(oracle), abi.encodeWithSelector(IOracle.getResponseIds.selector), abi.encode(_ids));
//     module.getResponseIds(requestId);
//   }

//   function test_listRequestsCallsOracle() public {
//     IOracle.FullRequest[] memory _list;
//     _mockAndExpect(address(oracle), abi.encodeWithSelector(IOracle.listRequests.selector), abi.encode(_list));
//     module.listRequests(0, 10);
//   }

//   function test_listRequestIdsCallsOracle() public {
//     bytes32[] memory _list;
//     _mockAndExpect(address(oracle), abi.encodeWithSelector(IOracle.listRequestIds.selector), abi.encode(_list));
//     module.listRequestIds(0, 10);
//   }

//   function test_getRequestIdCallsOracle(uint256 _nonce) public {
//     _mockAndExpect(address(oracle), abi.encodeWithSelector(IOracle.getRequestId.selector), abi.encode(bytes32(0)));
//     module.getRequestId(_nonce);
//   }

//   function test_getRequestByNonceCallsOracle(uint256 _nonce) public {
//     IOracle.Request memory _request;
//     _mockAndExpect(address(oracle), abi.encodeWithSelector(IOracle.getRequestByNonce.selector), abi.encode(_request));
//     module.getRequestByNonce(_nonce);
//   }

//   function test_finalizeCallsOracle() public {
//     _mockAndExpect(address(oracle), abi.encodeWithSignature('finalize(bytes32,bytes32)'), abi.encode());
//     vm.prank(address(submodule1));
//     module.finalize(requestId, responseId);
//   }

//   function test_escalateDisputeCallsOracle() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId);

//     _mockAndExpect(address(oracle), abi.encodeWithSelector(IOracle.escalateDispute.selector), abi.encode());

//     vm.prank(address(submodule1));
//     module.escalateDispute(disputeId);
//   }

//   function test_isParticipantCallsOracle(bytes32 _requestId, address _user) public {
//     _mockAndExpect(address(oracle), abi.encodeWithSelector(IOracle.isParticipant.selector), abi.encode(true));
//     module.isParticipant(_requestId, _user);
//   }

//   function test_getFinalizedResponseIdCallsOracle(bytes32 _requestId) public {
//     _mockAndExpect(
//       address(oracle), abi.encodeWithSelector(IOracle.getFinalizedResponseId.selector), abi.encode(bytes32('69'))
//     );
//     module.getFinalizedResponseId(_requestId);
//   }

//   function test_totalRequestCountCallsOracle() public {
//     _mockAndExpect(address(oracle), abi.encodeWithSelector(IOracle.totalRequestCount.selector), abi.encode(uint256(69)));
//     module.totalRequestCount();
//   }

//   function test_finalizeWithoutResponseCallsOracle() public {
//     _mockAndExpect(address(oracle), abi.encodeWithSignature('finalize(bytes32)'), abi.encode());
//     vm.prank(address(submodule1));
//     module.finalize(requestId);
//   }

//   function test_getDisputeCallsManager(bytes32 _disputeId) public {
//     IOracle.Dispute memory _dispute;
//     _mockAndExpect(address(oracle), abi.encodeWithSelector(IOracle.getDispute.selector), abi.encode(_dispute));
//     module.getDispute(_disputeId);
//   }
// }

// contract SequentialResolutionModule_Unit_ResolveDispute is BaseTest {
//   function test_revertIfNotOracle() public {
//     // Check: does it revert if not called by the Oracle?
//     vm.expectRevert(abi.encodeWithSelector(IModule.Module_OnlyOracle.selector));

//     vm.prank(makeAddr('other_sender'));
//     module.resolveDispute(disputeId);
//   }

//   function test_callsFirstModuleAndResolvesIfWon() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId);
//     submodule1.forTest_setResponseStatus(IOracle.DisputeStatus.Won);

//     // Check: is the module called with IOracle.updateDisputeStatus and DisputeStatus.Won?
//     vm.expectCall(
//       address(module),
//       abi.encodeWithSelector(IOracle.updateDisputeStatus.selector, disputeId, IOracle.DisputeStatus.Won)
//     );

//     // Check: is the oracle called with IOracle.updateDisputeStatus and DisputeStatus.Won?
//     vm.expectCall(
//       address(oracle),
//       abi.encodeWithSelector(IOracle.updateDisputeStatus.selector, disputeId, IOracle.DisputeStatus.Won)
//     );

//     vm.prank(address(oracle));
//     module.resolveDispute(disputeId);
//   }

//   function test_callsFirstModuleAndResolvesIfLost() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId);
//     submodule1.forTest_setResponseStatus(IOracle.DisputeStatus.Lost);

//     // Check: is the module called with IOracle.updateDisputeStatus and DisputeStatus.Lost?
//     vm.expectCall(
//       address(module),
//       abi.encodeWithSelector(IOracle.updateDisputeStatus.selector, disputeId, IOracle.DisputeStatus.Lost)
//     );

//     // Check: is the oracle called with IOracle.updateDisputeStatus and DisputeStatus.Lost?
//     vm.expectCall(
//       address(oracle),
//       abi.encodeWithSelector(IOracle.updateDisputeStatus.selector, disputeId, IOracle.DisputeStatus.Lost)
//     );

//     vm.prank(address(oracle));
//     module.resolveDispute(disputeId);
//   }

//   function test_goesToTheNextResolutionModule() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId);
//     submodule1.forTest_setResponseStatus(IOracle.DisputeStatus.NoResolution);

//     // Check: is the submodule 2 called with IResolutionModule.startResolution?
//     vm.expectCall(address(submodule2), abi.encodeWithSelector(IResolutionModule.startResolution.selector, disputeId));

//     // Check: is the current resolution module the submodule 1?
//     assertEq(address(module.getCurrentResolutionModule(disputeId)), address(submodule1));

//     vm.prank(address(oracle));
//     module.resolveDispute(disputeId);

//     // Check: is the current resolution module the submodule 2?
//     assertEq(address(module.getCurrentResolutionModule(disputeId)), address(submodule2));

//     // Check: is the submodule 2 called with IResolutionModule.resolveDispute?
//     vm.expectCall(address(submodule2), abi.encodeWithSelector(IResolutionModule.resolveDispute.selector, disputeId));

//     vm.prank(address(oracle));
//     module.resolveDispute(disputeId);
//   }

//   function test_callsTheManagerWhenThereAreNoMoreSubmodulesLeft() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId);

//     submodule1.forTest_setResponseStatus(IOracle.DisputeStatus.NoResolution);

//     vm.prank(address(oracle));
//     module.resolveDispute(disputeId);

//     submodule2.forTest_setResponseStatus(IOracle.DisputeStatus.NoResolution);

//     vm.prank(address(oracle));
//     module.resolveDispute(disputeId);

//     // Check: is the oracle called with IOracle.updateDisputeStatus and DisputeStatus.NoResolution?
//     vm.expectCall(
//       address(oracle),
//       abi.encodeWithSelector(IOracle.updateDisputeStatus.selector, disputeId, IOracle.DisputeStatus.NoResolution)
//     );

//     submodule3.forTest_setResponseStatus(IOracle.DisputeStatus.NoResolution);
//     vm.prank(address(oracle));
//     module.resolveDispute(disputeId);
//   }
// }

// contract SequentialResolutionModule_Unit_StartResolution is BaseTest {
//   function test_revertsIfNotOracle() public {
//     // Check: does it revert if not called by the Oracle?
//     vm.expectRevert(abi.encodeWithSelector(IModule.Module_OnlyOracle.selector));

//     vm.prank(makeAddr('other_sender'));
//     module.startResolution(disputeId);
//   }

//   function test_callsFirstModule() public {
//     // Check: is the submodule 1 called with IResolutionModule.startResolution?
//     vm.expectCall(address(submodule1), abi.encodeWithSelector(IResolutionModule.startResolution.selector, disputeId));

//     vm.prank(address(oracle));
//     module.startResolution(disputeId);
//   }

//   function test_callsFirstModuleSequence2() public {
//     // Check: is the submodule 2 called with IResolutionModule.startResolution?
//     vm.expectCall(address(submodule2), abi.encodeWithSelector(IResolutionModule.startResolution.selector, disputeId2));

//     vm.prank(address(oracle));
//     module.startResolution(disputeId2);
//   }

//   function test_newDispute() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId);

//     vm.prank(address(submodule1));
//     module.updateDisputeStatus(disputeId, IOracle.DisputeStatus.NoResolution);

//     // Check: is the submodule 2 stored as the current resolution module for the dispute?
//     assertEq(address(module.getCurrentResolutionModule(disputeId)), address(submodule2));

//     bytes32 _dispute3 = bytes32(uint256(6969));

//     _mockAndExpect(
//       address(oracle),
//       abi.encodeWithSelector(IOracle.getDispute.selector, _dispute3),
//       abi.encode(
//         IOracle.Dispute(block.timestamp, disputer, proposer, responseId, requestId, IOracle.DisputeStatus.Escalated)
//       )
//     );

//     vm.prank(address(oracle));
//     module.startResolution(_dispute3);

//     // Check: is the submodule 1 stored as the current resolution module for the dispute 3?
//     assertEq(address(module.getCurrentResolutionModule(_dispute3)), address(submodule1));
//   }
// }

// contract SequentialResolutionModule_Unit_UpdateDisputeStatus is BaseTest {
//   function test_revertsIfNotValidSubmodule() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId);
//     // Check: does it revert if not called by a submodule?

//     // Check: does it revert if not called by a submodule?
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_OnlySubmodule.selector)
//     );

//     vm.prank(makeAddr('other_sender'));
//     module.updateDisputeStatus(disputeId, IOracle.DisputeStatus.NoResolution);
//   }

//   function test_revertsIfNotSubmodule() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId);

//     // Check: does it revert if not called by a submodule?
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_OnlySubmodule.selector)
//     );

//     vm.prank(makeAddr('caller'));
//     module.updateDisputeStatus(disputeId, IOracle.DisputeStatus.NoResolution);
//   }

//   function test_revertsIfNotSubmoduleSequence2() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId2);

//     // Check: does it revert if not called by a submodule?
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_OnlySubmodule.selector)
//     );

//     vm.prank(makeAddr('caller'));
//     module.updateDisputeStatus(disputeId2, IOracle.DisputeStatus.NoResolution);
//   }

//   function test_changesCurrentIndex() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId);

//     // Check: is the submodule 2 called with IResolutionModule.startResolution?
//     vm.expectCall(address(submodule2), abi.encodeWithSelector(IResolutionModule.startResolution.selector, disputeId));

//     // Check: is the submodule 1 stored as the current resolution module for the dispute?
//     assertEq(address(module.getCurrentResolutionModule(disputeId)), address(submodule1));

//     vm.prank(address(submodule1));
//     module.updateDisputeStatus(disputeId, IOracle.DisputeStatus.NoResolution);

//     // Check: is the submodule 2 stored as the current resolution module for the dispute?
//     assertEq(address(module.getCurrentResolutionModule(disputeId)), address(submodule2));
//   }

//   function test_changesCurrentIndexSequence2() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId2);

//     // Check: is the submodule 3 called with IResolutionModule.startResolution?
//     vm.expectCall(address(submodule3), abi.encodeWithSelector(IResolutionModule.startResolution.selector, disputeId2));

//     // Check: is the submodule 2 stored as the current resolution module for the dispute?
//     assertEq(address(module.getCurrentResolutionModule(disputeId2)), address(submodule2));

//     vm.prank(address(submodule2));
//     module.updateDisputeStatus(disputeId2, IOracle.DisputeStatus.NoResolution);

//     // Check: is the submodule 3 stored as the current resolution module for the dispute?
//     assertEq(address(module.getCurrentResolutionModule(disputeId2)), address(submodule3));
//   }

//   function test_callsManagerWhenResolved() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId);

//     // Check: is the Oracle called with IOracle.updateDisputeStatus?
//     vm.expectCall(
//       address(oracle),
//       abi.encodeWithSelector(IOracle.updateDisputeStatus.selector, disputeId, IOracle.DisputeStatus.Won)
//     );

//     vm.prank(address(submodule1));
//     module.updateDisputeStatus(disputeId, IOracle.DisputeStatus.Won);
//   }

//   function test_callsManagerWhenResolvedSequence2() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId2);

//     // Check: is the Oracle called with IOracle.updateDisputeStatus?
//     vm.expectCall(
//       address(oracle),
//       abi.encodeWithSelector(IOracle.updateDisputeStatus.selector, disputeId2, IOracle.DisputeStatus.Won)
//     );

//     vm.prank(address(submodule2));
//     module.updateDisputeStatus(disputeId2, IOracle.DisputeStatus.Won);
//   }
// }

// contract SequentialResolutionModule_Unit_EscalateDispute is BaseTest {
//   function test_revertsIfNotSubmodule() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId);

//     // Check: does it revert if not called by a submodule?
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_OnlySubmodule.selector)
//     );
//     module.escalateDispute(disputeId);
//   }
// }

// contract SequentialResolutionModule_Unit_FinalizeRequest is BaseTest {
//   function test_finalizesAllSubmodules() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId);

//     // Check: are the submodules called with IModule.finalizeRequest?
//     vm.expectCall(address(submodule1), abi.encodeWithSelector(IModule.finalizeRequest.selector, requestId));
//     vm.expectCall(address(submodule2), abi.encodeWithSelector(IModule.finalizeRequest.selector, requestId));
//     vm.expectCall(address(submodule3), abi.encodeWithSelector(IModule.finalizeRequest.selector, requestId));

//     vm.prank(address(oracle));
//     module.finalizeRequest(requestId, address(oracle));
//   }

//   function test_revertsIfNotOracle() public {
//     // Check: does it revert if not called by the Oracle?
//     vm.expectRevert(abi.encodeWithSelector(IModule.Module_OnlyOracle.selector));

//     vm.prank(makeAddr('caller'));
//     module.finalizeRequest(requestId, makeAddr('caller'));
//   }

//   function test_revertsIfNotSubmodule() public {
//     vm.prank(address(oracle));
//     module.startResolution(disputeId);

//     // Check: does it revert if not called by a submodule?
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_OnlySubmodule.selector)
//     );
//     module.finalize(requestId, responseId);
//   }
// }

// contract SequentialResolutionModule_Unit_ListSubmodules is BaseTest {
//   function test_fullList() public {
//     IResolutionModule[] memory _submodules = module.listSubmodules(0, 3, 1);

//     // Check: do the stored submodules match?
//     assertEq(_submodules.length, 3);
//     assertEq(address(_submodules[0]), address(submodule1));
//     assertEq(address(_submodules[1]), address(submodule2));
//     assertEq(address(_submodules[2]), address(submodule3));
//   }

//   function test_fullListSequence2() public {
//     IResolutionModule[] memory _submodules = module.listSubmodules(0, 3, sequenceId2);

//     // Check: do the stored submodules match?
//     assertEq(_submodules.length, 3);
//     assertEq(address(_submodules[0]), address(submodule2));
//     assertEq(address(_submodules[1]), address(submodule3));
//     assertEq(address(_submodules[2]), address(submodule1));
//   }

//   function test_moreThanExist() public {
//     IResolutionModule[] memory _submodules = module.listSubmodules(0, 200, 1);

//     // Check: do the stored submodules match?
//     assertEq(_submodules.length, 3);
//     assertEq(address(_submodules[0]), address(submodule1));
//     assertEq(address(_submodules[1]), address(submodule2));
//     assertEq(address(_submodules[2]), address(submodule3));
//   }

//   function test_partialListMiddle() public {
//     IResolutionModule[] memory _submodules = module.listSubmodules(1, 2, 1);

//     // Check: do the stored submodules match?
//     assertEq(_submodules.length, 2);
//     assertEq(address(_submodules[0]), address(submodule2));
//     assertEq(address(_submodules[1]), address(submodule3));
//   }

//   function test_partialListStart() public {
//     IResolutionModule[] memory _submodules = module.listSubmodules(0, 2, sequenceId);

//     // Check: do the stored submodules match?
//     assertEq(_submodules.length, 2);
//     assertEq(address(_submodules[0]), address(submodule1));
//     assertEq(address(_submodules[1]), address(submodule2));
//   }
// }

// contract SequentialResolutionModule_Unit_NotImplemented is BaseTest {
//   function testReverts_disputeResponseNotSubmodule() public {
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_NotImplemented.selector)
//     );
//     module.disputeResponse(requestId, responseId);
//   }

//   function testReverts_proposeResponseNotSubmodule() public {
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_NotImplemented.selector)
//     );
//     module.proposeResponse(requestId, responseData);
//   }

//   function testReverts_proposeResponseWithProposerNotSubmodule() public {
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_NotImplemented.selector)
//     );
//     module.proposeResponse(proposer, requestId, responseData);
//   }

//   function testReverts_disputeResponseNotImplemented() public {
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_NotImplemented.selector)
//     );
//     vm.prank(address(submodule1));
//     module.disputeResponse(requestId, responseId);
//   }

//   function testReverts_proposeResponseNotImplemented() public {
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_NotImplemented.selector)
//     );
//     vm.prank(address(submodule1));
//     module.proposeResponse(requestId, responseData);
//   }

//   function testReverts_proposeResponseWithProposerNotImplemented() public {
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_NotImplemented.selector)
//     );
//     vm.prank(address(submodule1));
//     module.proposeResponse(proposer, requestId, responseData);
//   }

//   function testReverts_createRequestNotImplemented() public {
//     IOracle.NewRequest memory _request;
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_NotImplemented.selector)
//     );
//     vm.prank(address(submodule1));
//     module.createRequest(_request);
//   }

//   function testReverts_createRequestsNotImplemented() public {
//     IOracle.NewRequest[] memory _requests;
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_NotImplemented.selector)
//     );
//     vm.prank(address(submodule1));
//     module.createRequests(_requests);
//   }

//   function testReverts_deleteResponseNotImplemented() public {
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_NotImplemented.selector)
//     );
//     vm.prank(address(submodule1));
//     module.deleteResponse(requestId);
//   }

//   function testReverts_createRequestNotSubmodule() public {
//     IOracle.NewRequest memory _request;
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_NotImplemented.selector)
//     );
//     module.createRequest(_request);
//   }

//   function testReverts_createRequestsNotSubmodule() public {
//     IOracle.NewRequest[] memory _requests;
//     vm.expectRevert(
//       abi.encodeWithSelector(ISequentialResolutionModule.SequentialResolutionModule_NotImplemented.selector)
//     );
//     module.createRequests(_requests);
//   }
// }
