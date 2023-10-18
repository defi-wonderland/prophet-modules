// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {DSTestPlus} from '@defi-wonderland/solidity-utils/solidity/test/DSTestPlus.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';

import {IAccountingExtension} from '../../interfaces/extensions/IAccountingExtension.sol';

contract Helpers is DSTestPlus {
  modifier assumeFuzzable(address _address) {
    _assumeFuzzable(_address);
    _;
  }

  function _assumeFuzzable(address _address) internal {
    assumeNotForgeAddress(_address);
    assumeNotZeroAddress(_address);
    assumeNotPrecompile(_address);
  }

  function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
    vm.mockCall(_receiver, _calldata, _returned);
    vm.expectCall(_receiver, _calldata);
  }

  function _getMockDispute(
    bytes32 _requestId,
    address _disputer,
    address _proposer
  ) internal view returns (IOracle.Dispute memory _dispute) {
    _dispute = IOracle.Dispute({
      disputer: _disputer,
      responseId: bytes32('response'),
      proposer: _proposer,
      requestId: _requestId,
      status: IOracle.DisputeStatus.None,
      createdAt: block.timestamp
    });
  }

  function _forBondDepositERC20(
    IAccountingExtension _accountingExtension,
    address _depositor,
    IERC20 _token,
    uint256 _depositAmount,
    uint256 _balanceIncrease
  ) internal {
    vm.assume(_balanceIncrease >= _depositAmount);
    deal(address(_token), _depositor, _balanceIncrease);
    vm.startPrank(_depositor);
    _token.approve(address(_accountingExtension), _depositAmount);
    _accountingExtension.deposit(_token, _depositAmount);
    vm.stopPrank();
  }
}
