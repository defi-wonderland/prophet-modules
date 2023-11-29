// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IArbitrator} from '../../interfaces/IArbitrator.sol';

contract MockAtomicArbitrator is IArbitrator {
  IOracle.DisputeStatus public answer;
  IOracle public oracle;

  constructor(IOracle _oracle) {
    oracle = _oracle;
  }

  function resolve(
    IOracle.Request memory _request,
    IOracle.Response memory _response,
    IOracle.Dispute memory _dispute
  ) external returns (bytes memory _result) {
    _result = new bytes(0);
    answer = IOracle.DisputeStatus.Won;
    oracle.resolveDispute(_request, _response, _dispute);
  }

  function getAnswer(bytes32 /* _dispute */ ) external view returns (IOracle.DisputeStatus _answer) {
    _answer = answer;
  }

  function supportsInterface(bytes4 /* interfaceId */ ) external pure returns (bool _supported) {
    _supported = true;
  }
}
