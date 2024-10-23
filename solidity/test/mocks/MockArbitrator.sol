// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAccessController} from '@defi-wonderland/prophet-core/solidity/interfaces/IAccessController.sol';

import {IArbitrator, IOracle} from '../../interfaces/IArbitrator.sol';

contract MockArbitrator is IArbitrator {
  IOracle.DisputeStatus internal _answer = IOracle.DisputeStatus.Won;

  function setAnswer(IOracle.DisputeStatus _disputeStatus) external {
    _answer = _disputeStatus;
  }

  function resolve(
    IOracle.Request memory,
    IOracle.Response memory,
    IOracle.Dispute memory,
    IAccessController.AccessControl memory AccessControl
  ) external pure returns (bytes memory _result) {
    _result = new bytes(0);
  }

  function getAnswer(bytes32 /* _dispute */ ) external view returns (IOracle.DisputeStatus _disputeStatus) {
    _disputeStatus = _answer;
  }

  function supportsInterface(bytes4 /* interfaceId */ ) external pure returns (bool _supported) {
    _supported = true;
  }
}
