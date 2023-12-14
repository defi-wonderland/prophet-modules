// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// solhint-disable-next-line no-unused-import
import {IModule, Module} from '@defi-wonderland/prophet-core-contracts/solidity/contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';

import {IArbitrator} from '../../../interfaces/IArbitrator.sol';
import {IArbitratorModule} from '../../../interfaces/modules/resolution/IArbitratorModule.sol';

contract ArbitratorModule is Module, IArbitratorModule {
  /**
   * @notice The status of all disputes
   */
  mapping(bytes32 _disputeId => ArbitrationStatus _status) internal _disputeData;

  constructor(IOracle _oracle) Module(_oracle) {}

  /// @inheritdoc IModule
  function moduleName() external pure returns (string memory _moduleName) {
    return 'ArbitratorModule';
  }

  /// @inheritdoc IArbitratorModule
  function decodeRequestData(bytes calldata _data) public pure returns (RequestParameters memory _params) {
    _params = abi.decode(_data, (RequestParameters));
  }

  /// @inheritdoc IArbitratorModule
  function getStatus(bytes32 _disputeId) external view returns (ArbitrationStatus _disputeStatus) {
    _disputeStatus = _disputeData[_disputeId];
  }

  /// @inheritdoc IArbitratorModule
  function startResolution(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external onlyOracle {
    RequestParameters memory _params = decodeRequestData(_request.resolutionModuleData);
    if (_params.arbitrator == address(0)) revert ArbitratorModule_InvalidArbitrator();

    _disputeData[_disputeId] = ArbitrationStatus.Active;
    IArbitrator(_params.arbitrator).resolve(_request, _response, _dispute);

    emit ResolutionStarted(_dispute.requestId, _disputeId);
  }

  /// @inheritdoc IArbitratorModule
  function resolveDispute(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external onlyOracle {
    if (ORACLE.disputeStatus(_disputeId) != IOracle.DisputeStatus.Escalated) revert ArbitratorModule_InvalidDisputeId();

    RequestParameters memory _params = decodeRequestData(_request.resolutionModuleData);
    IOracle.DisputeStatus _status = IArbitrator(_params.arbitrator).getAnswer(_disputeId);

    if (_status <= IOracle.DisputeStatus.Escalated) revert ArbitratorModule_InvalidResolutionStatus();
    _disputeData[_disputeId] = ArbitrationStatus.Resolved;

    ORACLE.updateDisputeStatus(_request, _response, _dispute, _status);

    emit DisputeResolved(_dispute.requestId, _disputeId, _status);
  }
}
