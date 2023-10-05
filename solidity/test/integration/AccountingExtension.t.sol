// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_AccountingExtension is IntegrationBase {
  address public user = makeAddr('user');

  function test_depositERC20(uint256 _initialBalance, uint256 _depositAmount) public {
    vm.assume(_initialBalance >= _depositAmount);
    _forBondDepositERC20(_accountingExtension, user, usdc, _depositAmount, _initialBalance);
    // Check: is virtual balance updated?
    assertEq(_depositAmount, _accountingExtension.balanceOf(user, usdc));
    // Check: is token contract balance updated?
    assertEq(_initialBalance - _depositAmount, usdc.balanceOf(user));
  }

  function test_withdrawERC20(uint256 _initialBalance, uint256 _depositAmount, uint256 _withdrawAmount) public {
    vm.assume(_withdrawAmount <= _depositAmount);
    // Deposit some USDC
    _forBondDepositERC20(_accountingExtension, user, usdc, _depositAmount, _initialBalance);

    vm.prank(user);
    _accountingExtension.withdraw(usdc, _withdrawAmount);

    // Check: is virtual balance updated?
    assertEq(_depositAmount - _withdrawAmount, _accountingExtension.balanceOf(user, usdc));
    // Check: is token contract balance updated?
    assertEq(_initialBalance - _depositAmount + _withdrawAmount, usdc.balanceOf(user));
  }

  function test_depositERC20_invalidAmount(uint256 _initialBalance, uint256 _invalidDepositAmount) public {
    vm.assume(_invalidDepositAmount > _initialBalance);
    deal(address(usdc), user, _initialBalance);

    vm.startPrank(user);
    usdc.approve(address(_accountingExtension), _invalidDepositAmount);

    // Check: does it revert if trying to deposit an amount greater than balance?
    vm.expectRevert(bytes('ERC20: transfer amount exceeds balance'));

    _accountingExtension.deposit(usdc, _invalidDepositAmount);
    vm.stopPrank();
  }

  function test_withdrawERC20_insufficientFunds(
    uint256 _initialBalance,
    uint256 _depositAmount,
    uint256 _withdrawAmount
  ) public {
    vm.assume(_withdrawAmount > _depositAmount);
    _forBondDepositERC20(_accountingExtension, user, usdc, _depositAmount, _initialBalance);

    // Check: does it revert if trying to withdraw an amount greater than virtual balance?
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);
    vm.prank(user);
    _accountingExtension.withdraw(usdc, _withdrawAmount);
  }

  function test_withdrawETH_insufficientFunds(
    uint256 _initialBalance,
    uint256 _depositAmount,
    uint256 _withdrawAmount
  ) public {
    vm.assume(_withdrawAmount > _depositAmount);
    _forBondDepositERC20(_accountingExtension, user, IERC20(address(weth)), _depositAmount, _initialBalance);

    // Check: does it revert if trying to withdraw an amount greater than virtual balance?
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);
    vm.prank(user);
    _accountingExtension.withdraw(weth, _withdrawAmount);
  }

  function test_withdrawBondedFunds(uint256 _initialBalance, uint256 _bondAmount) public {
    vm.assume(_bondAmount > 0);
    _forBondDepositERC20(_accountingExtension, user, usdc, _bondAmount, _initialBalance);

    HttpRequestModule _requestModule = new HttpRequestModule(oracle);
    BondedResponseModule _responseModule = new BondedResponseModule(oracle);
    BondedDisputeModule _bondedDisputeModule = new BondedDisputeModule(oracle);

    IOracle.NewRequest memory _request = IOracle.NewRequest({
      requestModuleData: abi.encode(
        IHttpRequestModule.RequestParameters({
          url: '',
          method: IHttpRequestModule.HttpMethod.GET,
          body: '',
          accountingExtension: _accountingExtension,
          paymentToken: usdc,
          paymentAmount: _bondAmount
        })
        ),
      responseModuleData: abi.encode(
        IBondedResponseModule.RequestParameters({
          accountingExtension: _accountingExtension,
          bondToken: usdc,
          bondSize: _bondAmount,
          deadline: block.timestamp + BLOCK_TIME * 600,
          disputeWindow: _baseDisputeWindow
        })
        ),
      disputeModuleData: abi.encode(),
      resolutionModuleData: abi.encode(),
      finalityModuleData: abi.encode(),
      requestModule: _requestModule,
      responseModule: _responseModule,
      disputeModule: _bondedDisputeModule,
      resolutionModule: IResolutionModule(address(0)),
      finalityModule: IFinalityModule(address(0)),
      ipfsHash: _ipfsHash
    });

    vm.startPrank(user);
    _accountingExtension.approveModule(address(_requestModule));
    oracle.createRequest(_request);
    // Check: does it revert if trying to withdraw an amount that is bonded to a request?
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);
    _accountingExtension.withdraw(usdc, _bondAmount);
    vm.stopPrank();
  }
}
