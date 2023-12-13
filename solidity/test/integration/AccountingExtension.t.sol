// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IntegrationBase.sol';

contract Integration_AccountingExtension is IntegrationBase {
  address public user = makeAddr('user');

  function setUp() public override {
    super.setUp();

    // Full allowance for both tokens
    vm.prank(user);
    usdc.approve(address(_accountingExtension), type(uint256).max);

    vm.prank(user);
    weth.approve(address(_accountingExtension), type(uint256).max);
  }

  /**
   * @notice Depositing ERC20 should update the virtual balance and the token contract balance
   */
  function test_depositERC20(uint256 _initialBalance, uint256 _depositAmount) public {
    vm.assume(_initialBalance >= _depositAmount);
    _deposit(_accountingExtension, user, usdc, _depositAmount, _initialBalance);

    // Check: is virtual balance updated?
    assertEq(_depositAmount, _accountingExtension.balanceOf(user, usdc));

    // Check: is token contract balance updated?
    assertEq(_initialBalance - _depositAmount, usdc.balanceOf(user));
  }

  /**
   * @notice Depositing more than the user's balance should revert
   */
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

  /**
   * @notice Withdrawing ERC20 should update the virtual balance and the token contract balance
   */
  function test_withdrawERC20(uint256 _initialBalance, uint256 _depositAmount, uint256 _withdrawAmount) public {
    vm.assume(_withdrawAmount <= _depositAmount);
    _deposit(_accountingExtension, user, usdc, _depositAmount, _initialBalance);

    vm.prank(user);
    _accountingExtension.withdraw(usdc, _withdrawAmount);

    // Check: is virtual balance updated?
    assertEq(_depositAmount - _withdrawAmount, _accountingExtension.balanceOf(user, usdc));

    // Check: is token contract balance updated?
    assertEq(_initialBalance - _depositAmount + _withdrawAmount, usdc.balanceOf(user));
  }

  /**
   * @notice Withdrawing more than the user's virtual balance should revert
   */
  function test_withdrawERC20_insufficientFunds(
    uint256 _initialBalance,
    uint256 _depositAmount,
    uint256 _withdrawAmount
  ) public {
    vm.assume(_withdrawAmount > _depositAmount);
    _deposit(_accountingExtension, user, usdc, _depositAmount, _initialBalance);

    // Check: does it revert if trying to withdraw an amount greater than virtual balance?
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);
    vm.prank(user);
    _accountingExtension.withdraw(usdc, _withdrawAmount);
  }

  /**
   * @notice Withdrawing more WETH than was deposited by the user should revert
   */
  function test_withdrawETH_insufficientFunds(
    uint256 _initialBalance,
    uint256 _depositAmount,
    uint256 _withdrawAmount
  ) public {
    vm.assume(_withdrawAmount > _depositAmount);
    _deposit(_accountingExtension, user, weth, _depositAmount, _initialBalance);

    // Check: does it revert if trying to withdraw an amount greater than virtual balance?
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);
    vm.prank(user);
    _accountingExtension.withdraw(weth, _withdrawAmount);
  }

  /**
   * @notice Withdrawing the bonded funds should revert
   */
  function test_withdrawBondedFunds(uint256 _initialBalance, uint256 _bondAmount) public {
    vm.assume(_bondAmount > 0);
    _deposit(_accountingExtension, user, usdc, _bondAmount, _initialBalance);

    mockRequest.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _expectedUrl,
        body: _expectedBody,
        method: _expectedMethod,
        accountingExtension: _accountingExtension,
        paymentToken: usdc,
        paymentAmount: _bondAmount
      })
    );

    mockRequest.requester = user;

    vm.startPrank(user);
    _accountingExtension.approveModule(address(_requestModule));
    oracle.createRequest(mockRequest, _ipfsHash);

    // Check: does it revert if trying to withdraw an amount that is bonded to a request?
    vm.expectRevert(IAccountingExtension.AccountingExtension_InsufficientFunds.selector);
    _accountingExtension.withdraw(usdc, _bondAmount);
    vm.stopPrank();
  }

  /**
   * @notice Deposits the specified amount of tokens into the accounting extension
   *
   * @param _accounting The accounting extension
   * @param _depositor The depositor
   * @param _token The token to deposit
   * @param _depositAmount The amount to deposit
   * @param _balanceIncrease The amount to increase the depositor's initial balance by
   */
  function _deposit(
    IAccountingExtension _accounting,
    address _depositor,
    IERC20 _token,
    uint256 _depositAmount,
    uint256 _balanceIncrease
  ) internal {
    vm.assume(_balanceIncrease >= _depositAmount);
    deal(address(_token), _depositor, _balanceIncrease);

    vm.prank(_depositor);
    _accounting.deposit(_token, _depositAmount);
  }
}
