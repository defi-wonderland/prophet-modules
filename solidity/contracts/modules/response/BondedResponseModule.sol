// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IBondedResponseModule} from '../../../interfaces/modules/response/IBondedResponseModule.sol';

import {IModule, Module} from '@defi-wonderland/prophet-core/solidity/contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';

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
      // If the dispute was lost, we assume the proposed answer was correct.
      // DisputeStatus.None should not be reachable due to the previous check.
      if (_status == IOracle.DisputeStatus.Lost) revert BondedResponseModule_AlreadyResponded();
    }

    if (_sender != _response.proposer) {
      _params.accountingExtension.bond({
        _bonder: _response.proposer,
        _requestId: _response.requestId,
        _token: _params.bondToken,
        _amount: _params.bondSize,
        _sender: _sender
      });
    } else {
      _params.accountingExtension.bond({
        _bonder: _response.proposer,
        _requestId: _response.requestId,
        _token: _params.bondToken,
        _amount: _params.bondSize
      });
    }

    emit ResponseProposed(_response.requestId, _response, block.number);
  }

  /// @inheritdoc IBondedResponseModule
  function finalizeRequest(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    address _finalizer
  ) external override(IBondedResponseModule, Module) onlyOracle {
    RequestParameters memory _params = decodeRequestData(_request.responseModuleData);

    bool _isModule = ORACLE.allowedModule(_response.requestId, _finalizer);

    if (!_isModule && block.number < _params.deadline) {
      revert BondedResponseModule_TooEarlyToFinalize();
    }

    uint256 _responseCreatedAt = ORACLE.responseCreatedAt(_getId(_response));

    if (_responseCreatedAt != 0) {
      if (!_isModule && block.number < _responseCreatedAt + _params.disputeWindow) {
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
  function releaseUnutilizedResponse(IOracle.Request calldata _request, IOracle.Response calldata _response) external {
    bytes32 _responseId = _validateResponse(_request, _response);
    bytes32 _disputeId = ORACLE.disputeOf(_responseId);

    if (_disputeId > 0) {
      IOracle.DisputeStatus _disputeStatus = ORACLE.disputeStatus(_disputeId);
      if (_disputeStatus != IOracle.DisputeStatus.Lost && _disputeStatus != IOracle.DisputeStatus.NoResolution) {
        revert BondedResponseModule_InvalidReleaseParameters();
      }
    }

    bytes32 _finalizedResponseId = ORACLE.finalizedResponseId(_response.requestId);
    if (_finalizedResponseId == _responseId || _finalizedResponseId == bytes32(0)) {
      revert BondedResponseModule_InvalidReleaseParameters();
    }

    RequestParameters memory _params = decodeRequestData(_request.responseModuleData);
    _params.accountingExtension.release({
      _bonder: _response.proposer,
      _requestId: _response.requestId,
      _token: _params.bondToken,
      _amount: _params.bondSize
    });

    emit UnutilizedResponseReleased(_response.requestId, _responseId);
  }

  /// @inheritdoc IModule
  function validateParameters(bytes calldata _encodedParameters)
    external
    pure
    override(Module, IModule)
    returns (bool _valid)
  {
    RequestParameters memory _params = decodeRequestData(_encodedParameters);
    _valid = address(_params.accountingExtension) != address(0) && address(_params.bondToken) != address(0)
      && _params.bondSize != 0 && _params.disputeWindow != 0 && _params.deadline != 0;
  }
}
