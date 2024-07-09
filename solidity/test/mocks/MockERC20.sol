// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract MockERC20 is ERC20 {
  mapping(address _account => mapping(uint256 _callCount => uint256 _amount)) internal _balancesPerCall;
  mapping(address _account => uint256 _callCount) internal _callsPerAccount;
  bool internal _mocked;

  constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

  function mockBalanceOfPerCall(address _account, uint256 _callCount, uint256 _amount) external {
    _balancesPerCall[_account][_callCount] = _amount;
    _mocked = true;
  }

  function balanceOf(address _account) public view virtual override returns (uint256 _amount) {
    if (_mocked) {
      _amount = _balancesPerCall[_account][_callsPerAccount[_account]];
    } else {
      _amount = super.balanceOf(_account);
    }
  }

  function transfer(address _to, uint256 _amount) public virtual override returns (bool _success) {
    if (_mocked) {
      ++_callsPerAccount[msg.sender];
      ++_callsPerAccount[_to];
    }
    return super.transfer(_to, _amount);
  }

  function transferFrom(address _from, address _to, uint256 _amount) public virtual override returns (bool _success) {
    if (_mocked) {
      ++_callsPerAccount[_from];
      ++_callsPerAccount[_to];
    }
    return super.transferFrom(_from, _to, _amount);
  }

  function mint(address _account, uint256 _amount) public virtual {
    _mint(_account, _amount);
  }

  function burn(address _account, uint256 _amount) public virtual {
    _burn(_account, _amount);
  }

  function approve(address _owner, address _spender, uint256 _amount) public virtual {
    _approve(_owner, _spender, _amount);
  }
}
