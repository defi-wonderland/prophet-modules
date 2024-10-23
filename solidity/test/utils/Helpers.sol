// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {TestConstants} from './TestConstants.sol';
import {IAccessController} from '@defi-wonderland/prophet-core/solidity/interfaces/IAccessController.sol';
import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';
import {DSTestPlus} from '@defi-wonderland/solidity-utils/solidity/test/DSTestPlus.sol';

contract Helpers is DSTestPlus, TestConstants {
  // Placeholder addresses
  address public disputer = makeAddr('disputer');
  address public proposer = makeAddr('proposer');

  // Mock objects
  IOracle.Request public mockRequest = IOracle.Request({
    accessControlModule: address(0),
    requestModule: address(0),
    responseModule: address(0),
    disputeModule: address(0),
    resolutionModule: address(0),
    finalityModule: address(0),
    requestModuleData: bytes(''),
    responseModuleData: bytes(''),
    disputeModuleData: bytes(''),
    resolutionModuleData: bytes(''),
    finalityModuleData: bytes(''),
    requester: address(this),
    nonce: 1
  });

  IAccessController.AccessControl public mockAccessControl =
    IAccessController.AccessControl({user: address(0), data: bytes('')});

  bytes32 internal _mockRequestId = keccak256(abi.encode(mockRequest));

  IOracle.Response public mockResponse =
    IOracle.Response({proposer: proposer, requestId: _mockRequestId, response: bytes('')});

  bytes32 internal _mockResponseId = keccak256(abi.encode(mockResponse));

  IOracle.Dispute public mockDispute =
    IOracle.Dispute({disputer: disputer, responseId: _mockResponseId, proposer: proposer, requestId: _mockRequestId});

  bytes32 internal _mockDisputeId = keccak256(abi.encode(mockDispute));

  // Shared events that all modules emit
  event RequestFinalized(bytes32 indexed _requestId, IOracle.Response _response, address _finalizer);

  modifier assumeFuzzable(address _address) {
    _assumeFuzzable(_address);
    _;
  }

  function _getResponse(
    IOracle.Request memory _request,
    address _proposer
  ) internal pure returns (IOracle.Response memory _response) {
    return IOracle.Response({proposer: _proposer, requestId: _getId(_request), response: bytes('')});
  }

  function _getDispute(
    IOracle.Request memory _request,
    IOracle.Response memory _response
  ) internal view returns (IOracle.Dispute memory _dispute) {
    return IOracle.Dispute({
      disputer: disputer,
      responseId: _getId(_response),
      proposer: proposer,
      requestId: _getId(_request)
    });
  }

  function _getResponseAndDispute(IOracle _oracle)
    internal
    returns (IOracle.Response memory _response, IOracle.Dispute memory _dispute)
  {
    (_response, _dispute) = _getResponseAndDispute(_oracle, block.timestamp + 1 minutes);
  }

  function _getResponseAndDispute(
    IOracle _oracle,
    uint256 _disputeCreatedAt
  ) internal returns (IOracle.Response memory _response, IOracle.Dispute memory _dispute) {
    // Compute proper IDs
    _response = _getResponse(mockRequest, proposer);
    _dispute = _getDispute(mockRequest, _response);
    bytes32 _disputeId = _getId(_dispute);

    // Mock and expect IOracle.disputeCreatedAt to be called
    _mockAndExpect(
      address(_oracle), abi.encodeCall(IOracle.disputeCreatedAt, (_disputeId)), abi.encode(_disputeCreatedAt)
    );
  }

  /**
   * @notice Ensures that a fuzzed address can be used for deployment and calls
   *
   * @param _address The address to check
   */
  function _assumeFuzzable(address _address) internal view {
    assumeNotForgeAddress(_address);
    assumeNotZeroAddress(_address);
    assumeNotPrecompile(_address, block.chainid); // using Optimism chaind id for precompiles filtering
  }

  /**
   * @notice Sets up a mock and expects a call to it
   *
   * @param _receiver The address to have a mock on
   * @param _calldata The calldata to mock and expect
   * @param _returned The data to return from the mocked call
   */
  function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
    vm.mockCall(_receiver, _calldata, _returned);
    vm.expectCall(_receiver, _calldata);
  }

  /**
   * @notice Computes the ID of a given request as it's done in the Oracle
   *
   * @param _request The request to compute the ID for
   * @return _id The ID of the request
   */
  function _getId(IOracle.Request memory _request) internal pure returns (bytes32 _id) {
    _id = keccak256(abi.encode(_request));
  }

  /**
   * @notice Computes the ID of a given response as it's done in the Oracle
   *
   * @param _response The response to compute the ID for
   * @return _id The ID of the response
   */
  function _getId(IOracle.Response memory _response) internal pure returns (bytes32 _id) {
    _id = keccak256(abi.encode(_response));
  }

  /**
   * @notice Computes the ID of a given dispute as it's done in the Oracle
   *
   * @param _dispute The dispute to compute the ID for
   * @return _id The ID of the dispute
   */
  function _getId(IOracle.Dispute memory _dispute) internal pure returns (bytes32 _id) {
    _id = keccak256(abi.encode(_dispute));
  }

  /**
   * @notice Creates a mock contract, labels it and erases the bytecode
   *
   * @param _label The label to use for the mock contract
   * @return _contract The address of the mock contract
   */
  function _mockContract(string memory _label) internal returns (address _contract) {
    _contract = makeAddr(_label);
    vm.etch(_contract, hex'69');
  }

  /**
   * @notice Sets an expectation for an event to be emitted
   *
   * @param _contract The contract to expect the event on
   */
  function _expectEmit(address _contract) internal {
    vm.expectEmit(true, true, true, true, _contract);
  }

  function _createAccessControl() internal returns (IAccessController.AccessControl memory _accessControl) {
    _accessControl = _createAccessControl(msg.sender);
  }

  function _createAccessControl(address _user) internal returns (IAccessController.AccessControl memory _accessControl) {
    _accessControl = IAccessController.AccessControl({user: _user, data: bytes('')});
  }
}
