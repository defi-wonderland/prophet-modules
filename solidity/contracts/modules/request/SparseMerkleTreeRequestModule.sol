// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IModule, Module} from '@defi-wonderland/prophet-core/solidity/contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';

import {ISparseMerkleTreeRequestModule} from '../../../interfaces/modules/request/ISparseMerkleTreeRequestModule.sol';

contract SparseMerkleTreeRequestModule is Module, ISparseMerkleTreeRequestModule {
  constructor(IOracle _oracle) Module(_oracle) {}

  /// @inheritdoc IModule
  function moduleName() public pure returns (string memory _moduleName) {
    _moduleName = 'SparseMerkleTreeRequestModule';
  }

  /// @inheritdoc ISparseMerkleTreeRequestModule
  function decodeRequestData(bytes calldata _data) public pure returns (RequestParameters memory _params) {
    _params = abi.decode(_data, (RequestParameters));
  }

  /// @inheritdoc ISparseMerkleTreeRequestModule
  function createRequest(bytes32 _requestId, bytes calldata _data, address _requester) external onlyOracle {
    RequestParameters memory _params = decodeRequestData(_data);

    _params.accountingExtension.bond({
      _bonder: _requester,
      _requestId: _requestId,
      _token: _params.paymentToken,
      _amount: _params.paymentAmount
    });
  }

  /// @inheritdoc ISparseMerkleTreeRequestModule
  function finalizeRequest(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    address _finalizer
  ) external override(ISparseMerkleTreeRequestModule, Module) onlyOracle {
    RequestParameters memory _params = decodeRequestData(_request.requestModuleData);

    if (ORACLE.responseCreatedAt(_getId(_response)) != 0) {
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

  /// @inheritdoc IModule
  function validateParameters(bytes calldata _encodedParameters)
    external
    pure
    override(Module, IModule)
    returns (bool _valid)
  {
    RequestParameters memory _params = decodeRequestData(_encodedParameters);
    _valid = address(_params.accountingExtension) != address(0) && address(_params.paymentToken) != address(0)
      && address(_params.treeVerifier) != address(0) && _params.paymentAmount != 0 && _params.treeData.length != 0
      && _params.leavesToInsert.length != 0;
  }
}
