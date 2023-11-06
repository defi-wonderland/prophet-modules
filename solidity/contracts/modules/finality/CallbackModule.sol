// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// solhint-disable-next-line no-unused-import
import {Module, IModule} from '@defi-wonderland/prophet-core-contracts/solidity/contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';

import {ICallbackModule} from '../../../interfaces/modules/finality/ICallbackModule.sol';

contract CallbackModule is Module, ICallbackModule {
  constructor(IOracle _oracle) Module(_oracle) {}

  /// @inheritdoc IModule
  function moduleName() public pure returns (string memory _moduleName) {
    _moduleName = 'CallbackModule';
  }

  /// @inheritdoc ICallbackModule
  function decodeRequestData(bytes calldata _data) public pure returns (RequestParameters memory _params) {
    _params = abi.decode(_data, (RequestParameters));
  }

  /// @inheritdoc ICallbackModule
  function finalizeRequest(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    address _finalizer
  ) external override(Module, ICallbackModule) onlyOracle {
    RequestParameters memory _params = decodeRequestData(_request.finalityModuleData);
    _params.target.call(_params.data);
    emit Callback(_response.requestId, _params.target, _params.data);
    emit RequestFinalized(_response.requestId, _finalizer);
  }
}
