// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// solhint-disable-next-line no-unused-import
import {IModule, Module} from '@defi-wonderland/prophet-core-contracts/solidity/contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';

import {IContractCallRequestModule} from '../../../interfaces/modules/request/IContractCallRequestModule.sol';

contract ContractCallRequestModule is Module, IContractCallRequestModule {
  constructor(IOracle _oracle) Module(_oracle) {}

  /// @inheritdoc IModule
  function moduleName() public pure returns (string memory _moduleName) {
    _moduleName = 'ContractCallRequestModule';
  }

  /// @inheritdoc IContractCallRequestModule
  function decodeRequestData(bytes calldata _data) public pure returns (RequestParameters memory _params) {
    _params = abi.decode(_data, (RequestParameters));
  }

  /// @inheritdoc IContractCallRequestModule
  function createRequest(bytes32 _requestId, bytes calldata _data, address _requester) external onlyOracle {
    RequestParameters memory _params = decodeRequestData(_data);

    _params.accountingExtension.bond({
      _bonder: _requester,
      _requestId: _requestId,
      _token: _params.paymentToken,
      _amount: _params.paymentAmount
    });
  }

  /// @inheritdoc IContractCallRequestModule
  function finalizeRequest(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    address _finalizer
  ) external override(IContractCallRequestModule, Module) onlyOracle {
    RequestParameters memory _params = decodeRequestData(_request.requestModuleData);

    if (ORACLE.createdAt(_getId(_response)) != 0) {
      _params.accountingExtension.pay({
        _requestId: _response.requestId,
        _payer: _request.requester,
        _receiver: _response.proposer,
        _token: _params.paymentToken,
        _amount: _params.paymentAmount
      });
    } else {
      _params.accountingExtension.release({
        _bonder: _request.requester,
        _requestId: _response.requestId,
        _token: _params.paymentToken,
        _amount: _params.paymentAmount
      });
    }

    emit RequestFinalized(_response.requestId, _response, _finalizer);
  }
}
