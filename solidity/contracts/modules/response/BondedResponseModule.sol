// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// solhint-disable-next-line no-unused-import
import {Module, IModule} from '@defi-wonderland/prophet-core-contracts/solidity/contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';
import {IBondedResponseModule} from '../../../interfaces/modules/response/IBondedResponseModule.sol';

contract BondedResponseModule is Module, IBondedResponseModule {
  constructor(IOracle _oracle) Module(_oracle) {}

  /// @inheritdoc IModule
  function moduleName() public pure returns (string memory _moduleName) {
    _moduleName = 'BondedResponseModule';
  }

  /// @inheritdoc IBondedResponseModule
  function decodeRequestData(bytes calldata _data) public pure returns (RequestParameters memory _params) {
    _params = abi.decode(_data, (RequestParameters));
  }

  /// @inheritdoc IBondedResponseModule
  function propose(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    address _sender
  ) external onlyOracle {
    RequestParameters memory _params = decodeRequestData(_request.responseModuleData);

    // Cannot propose after the deadline
    if (block.timestamp >= _params.deadline) revert BondedResponseModule_TooLateToPropose();

    // Cannot propose to a request with a response, unless the response is being disputed
    bytes32[] memory _responseIds = ORACLE.getResponseIds(_response.requestId);
    uint256 _responsesLength = _responseIds.length;

    if (_responsesLength != 0) {
      bytes32 _disputeId = ORACLE.disputeOf(_responseIds[_responsesLength - 1]);

      // Allowing one undisputed response at a time
      if (_disputeId == bytes32(0)) revert BondedResponseModule_AlreadyResponded();
      IOracle.DisputeStatus _status = ORACLE.disputeStatus(_disputeId);
      // TODO: leaving a note here to re-check this check if a new status is added
      // If the dispute was lost, we assume the proposed answer was correct. DisputeStatus.None should not be reachable due to the previous check.
      if (_status == IOracle.DisputeStatus.Lost) revert BondedResponseModule_AlreadyResponded();
    }

    _params.accountingExtension.bond({
      _bonder: _response.proposer,
      _requestId: _response.requestId,
      _token: _params.bondToken,
      _amount: _params.bondSize,
      _sender: _sender
    });

    emit ResponseProposed(_response.requestId, _response, block.number);
  }

  /// @inheritdoc IBondedResponseModule
  function finalizeRequest(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    address _finalizer
  ) external override(IBondedResponseModule, Module) onlyOracle {
    RequestParameters memory _params = decodeRequestData(_request.responseModuleData);

    // TODO: If deadline has passed, we can skip the caller validation
    bool _isModule = ORACLE.allowedModule(_response.requestId, _finalizer);

    if (!_isModule && block.timestamp < _params.deadline) {
      revert BondedResponseModule_TooEarlyToFinalize();
    }

    uint256 _responseCreatedAt = ORACLE.createdAt(_getId(_response));

    if (_responseCreatedAt != 0) {
      if (!_isModule && block.timestamp < _responseCreatedAt + _params.disputeWindow) {
        revert BondedResponseModule_TooEarlyToFinalize();
      }

      _params.accountingExtension.release({
        _bonder: _response.proposer,
        _requestId: _response.requestId,
        _token: _params.bondToken,
        _amount: _params.bondSize
      });
    }

    emit RequestFinalized(_response.requestId, _response, _finalizer);
  }

  /// @inheritdoc IBondedResponseModule
  function releaseUncalledResponse(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external {
    bytes32 _disputeId = _validateDispute(_request, _response, _dispute);

    if (ORACLE.disputeStatus(_disputeId) != IOracle.DisputeStatus.Won) {
      revert BondedResponseModule_InvalidReleaseParameters();
    }

    bytes32 _finalizedResponseId = ORACLE.getFinalizedResponseId(_response.requestId);
    if (_finalizedResponseId == _dispute.responseId || _finalizedResponseId == bytes32(0)) {
      revert BondedResponseModule_InvalidReleaseParameters();
    }

    RequestParameters memory _params = decodeRequestData(_request.responseModuleData);
    _params.accountingExtension.release({
      _bonder: _response.proposer,
      _requestId: _response.requestId,
      _token: _params.bondToken,
      _amount: _params.bondSize
    });
  }
}
