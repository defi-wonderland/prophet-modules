// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// solhint-disable-next-line no-unused-import
import {Module, IModule} from '@defi-wonderland/prophet-core-contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/contracts/IOracle.sol';

import {ICallbackModule} from '../../../interfaces/modules/finality/ICallbackModule.sol';

contract CallbackModule is Module, ICallbackModule {
  constructor(IOracle _oracle) Module(_oracle) {}

  /// @inheritdoc IModule
  function moduleName() public pure returns (string memory _moduleName) {
    _moduleName = 'CallbackModule';
  }

  /// @inheritdoc ICallbackModule
  function decodeRequestData(bytes32 _requestId) public view returns (RequestParameters memory _params) {
    _params = abi.decode(requestData[_requestId], (RequestParameters));
  }

  /**
   * @notice Checks if the target address has code (i.e. is a contract)
   * @param _data The encoded data for the request
   */
  function _afterSetupRequest(bytes32, bytes calldata _data) internal view override {
    RequestParameters memory _params = abi.decode(_data, (RequestParameters));
    if (_params.target.code.length == 0) revert CallbackModule_TargetHasNoCode();
  }

  /// @inheritdoc ICallbackModule
  function finalizeRequest(
    bytes32 _requestId,
    address _finalizer
  ) external override(Module, ICallbackModule) onlyOracle {
    RequestParameters memory _params = decodeRequestData(_requestId);
    _params.target.call(_params.data);
    emit Callback(_requestId, _params.target, _params.data);
    emit RequestFinalized(_requestId, _finalizer);
  }
}
