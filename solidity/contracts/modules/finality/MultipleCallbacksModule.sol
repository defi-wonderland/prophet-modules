// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IModule, Module} from '@defi-wonderland/prophet-core/solidity/contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';

import {IProphetCallback} from '../../../interfaces/IProphetCallback.sol';
import {IMultipleCallbacksModule} from '../../../interfaces/modules/finality/IMultipleCallbacksModule.sol';

contract MultipleCallbacksModule is Module, IMultipleCallbacksModule {
  constructor(IOracle _oracle) Module(_oracle) {}

  /// @inheritdoc IMultipleCallbacksModule
  function decodeRequestData(bytes calldata _data) public pure returns (RequestParameters memory _params) {
    _params = abi.decode(_data, (RequestParameters));
  }

  /// @inheritdoc IModule
  function moduleName() public pure returns (string memory _moduleName) {
    _moduleName = 'MultipleCallbacksModule';
  }

  /// @inheritdoc IMultipleCallbacksModule
  function finalizeRequest(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    address _finalizer
  ) external override(IMultipleCallbacksModule, Module) onlyOracle {
    RequestParameters memory _params = decodeRequestData(_request.finalityModuleData);
    uint256 _length = _params.targets.length;

    for (uint256 _i; _i < _length;) {
      // purposely skips the return data, so we don't care if the call succeeds or fails
      _params.targets[_i].call(abi.encodeCall(IProphetCallback.prophetCallback, (_params.data[_i])));
      emit Callback(_response.requestId, _params.targets[_i], _params.data[_i]);
      unchecked {
        ++_i;
      }
    }

    emit RequestFinalized(_response.requestId, _response, _finalizer);
  }

  /// @inheritdoc IModule
  function validateParameters(bytes calldata _encodedParameters)
    external
    view
    override(Module, IModule)
    returns (bool _valid)
  {
    RequestParameters memory _params = decodeRequestData(_encodedParameters);
    _valid = true;

    for (uint256 _i; _i < _params.targets.length; ++_i) {
      if (!_targetHasBytecode(_params.targets[_i])) {
        _valid = false;
        break;
      }
    }

    for (uint256 _i; _i < _params.data.length; ++_i) {
      if (_params.data[_i].length == 0) {
        _valid = false;
        break;
      }
    }
  }

  /**
   * @notice Checks if a target address has bytecode
   * @param _target The address to check
   * @return _hasBytecode Whether the target has bytecode or not
   */
  function _targetHasBytecode(address _target) private view returns (bool _hasBytecode) {
    uint256 _size;
    assembly {
      _size := extcodesize(_target)
    }
    _hasBytecode = _size > 0;
  }
}
