// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {DSTestPlus} from '@defi-wonderland/solidity-utils/solidity/test/DSTestPlus.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IAccountingExtension} from '../../interfaces/extensions/IAccountingExtension.sol';
import {TestConstants} from './TestConstants.sol';

contract Helpers is DSTestPlus, TestConstants {
  // 100% random sequence of bytes representing request, response, or dispute id
  bytes32 public mockId = bytes32('69');

  // Placeholder addresses
  address public disputer = makeAddr('disputer');
  address public proposer = makeAddr('proposer');

  // Mock objects
  IOracle.Request public mockRequest;
  IOracle.Response public mockResponse = IOracle.Response({proposer: proposer, requestId: mockId, response: bytes('')});
  IOracle.Dispute public mockDispute =
    IOracle.Dispute({disputer: disputer, responseId: mockId, proposer: proposer, requestId: mockId});

  // Shared events that all modules emit
  event RequestFinalized(bytes32 indexed _requestId, IOracle.Response _response, address _finalizer);

  modifier assumeFuzzable(address _address) {
    _assumeFuzzable(_address);
    _;
  }

  /**
   * @notice Ensures that a fuzzed address can be used for deployment and calls
   *
   * @param _address The address to check
   */
  function _assumeFuzzable(address _address) internal view {
    assumeNotForgeAddress(_address);
    assumeNotZeroAddress(_address);
    assumeNotPrecompile(_address, block.chainid); // using Optimsim chaind id for precompiles filtering
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
}
