// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {DSTestPlus} from '@defi-wonderland/solidity-utils/solidity/test/DSTestPlus.sol';
import {IOracle} from '@defi-wonderland/prophet-core-abi/contracts/IOracle.sol';

import {IAccountingExtension} from '../../interfaces/extensions/IAccountingExtension.sol';

contract Helpers is DSTestPlus {
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
