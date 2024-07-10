// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract MockERC20Proxy {
  IERC20 public token;

  mapping(uint256 _callCount => mapping(address _account => uint256 _amount)) internal _balancesPerCall;
  uint256 internal _calls;
  bool internal _mocked;

  constructor(IERC20 _token) {
    token = _token;
  }

  function mockBalanceOfPerCall(uint256 _callCount, address _account, uint256 _amount) external {
    _balancesPerCall[_callCount][_account] = _amount;
    _mocked = true;
  }

  function balanceOf(address _account) external view returns (uint256 _amount) {
    if (_mocked) {
      _amount = _balancesPerCall[_calls][_account];
    } else {
      _amount = token.balanceOf(_account);
    }
  }

  fallback() external {
    if (_mocked) {
      ++_calls;
    }
    (bool _success,) = address(token).call(msg.data);
    require(_success, 'MockERC20Proxy: call failed');
  }
}
