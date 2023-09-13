// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IHttpRequestModule} from '../../interfaces/modules/IHttpRequestModule.sol';
import {IAccountingExtension} from '../../interfaces/extensions/IAccountingExtension.sol';
import {IOracle} from '../../interfaces/IOracle.sol';
import {Module} from '../Module.sol';

contract HttpRequestModule is Module, IHttpRequestModule {
  constructor(IOracle _oracle) Module(_oracle) {}

  function moduleName() public pure returns (string memory _moduleName) {
    _moduleName = 'HttpRequestModule';
  }

  /// @inheritdoc IHttpRequestModule
  function decodeRequestData(bytes32 _requestId)
    public
    view
    returns (
      string memory _url,
      HttpMethod _method,
      string memory _body,
      IAccountingExtension _accountingExtension,
      IERC20 _paymentToken,
      uint256 _paymentAmount
    )
  {
    (_url, _method, _body, _accountingExtension, _paymentToken, _paymentAmount) =
      abi.decode(requestData[_requestId], (string, HttpMethod, string, IAccountingExtension, IERC20, uint256));
  }

  /**
   * @notice Bonds the requester tokens to use as payment for the response proposer.
   */
  function _afterSetupRequest(bytes32 _requestId, bytes calldata) internal override {
    (,,, IAccountingExtension _accountingExtension, IERC20 _paymentToken, uint256 _paymentAmount) =
      decodeRequestData(_requestId);
    IOracle.Request memory _request = ORACLE.getRequest(_requestId);
    _accountingExtension.bond(_request.requester, _requestId, _paymentToken, _paymentAmount);
  }

  /// @inheritdoc IHttpRequestModule
  function finalizeRequest(
    bytes32 _requestId,
    address _finalizer
  ) external override(IHttpRequestModule, Module) onlyOracle {
    IOracle.Request memory _request = ORACLE.getRequest(_requestId);
    IOracle.Response memory _response = ORACLE.getFinalizedResponse(_requestId);
    (,,, IAccountingExtension _accountingExtension, IERC20 _paymentToken, uint256 _paymentAmount) =
      decodeRequestData(_requestId);
    if (_response.createdAt != 0) {
      _accountingExtension.pay(_requestId, _request.requester, _response.proposer, _paymentToken, _paymentAmount);
    } else {
      _accountingExtension.release(_request.requester, _requestId, _paymentToken, _paymentAmount);
    }
    emit RequestFinalized(_requestId, _finalizer);
  }
}
