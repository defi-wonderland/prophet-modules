// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract MockERC20 {
  mapping(address _account => mapping(uint256 _callCount => uint256 _amount)) internal _balancesPerCall;
  mapping(address _account => uint256 _callCount) internal _callsPerAccount;

  function balanceOf(address _account) external returns (uint256 _amount) {
    _amount = _balancesPerCall[_account][_callsPerAccount[_account]++];
  }

  function mockBalanceOfPerCall(address _account, uint256 _callCount, uint256 _amount) external {
    _balancesPerCall[_account][_callCount] = _amount;
  }
}
