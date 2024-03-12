// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// solhint-disable-next-line no-unused-import
import {IModule, Module} from '@defi-wonderland/prophet-core-contracts/solidity/contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';

import {ICircuitResolverModule} from '../../../interfaces/modules/dispute/ICircuitResolverModule.sol';

contract CircuitResolverModule is Module, ICircuitResolverModule {
  /// @notice Keeps track of the correct responses to requests
  mapping(bytes32 _requestId => bytes _correctResponse) internal _correctResponses;

  constructor(IOracle _oracle) Module(_oracle) {}

  /// @inheritdoc IModule
  function moduleName() external pure returns (string memory _moduleName) {
    return 'CircuitResolverModule';
  }

  /// @inheritdoc ICircuitResolverModule
  function decodeRequestData(bytes calldata _data) public pure returns (RequestParameters memory _params) {
    _params = abi.decode(_data, (RequestParameters));
  }

  /// @inheritdoc ICircuitResolverModule
  function onDisputeStatusChange(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external onlyOracle {
    RequestParameters memory _params = decodeRequestData(_request.disputeModuleData);
    IOracle.DisputeStatus _status = ORACLE.disputeStatus(_disputeId);

    if (_status == IOracle.DisputeStatus.Won) {
      _params.accountingExtension.pay({
        _requestId: _dispute.requestId,
        _payer: _dispute.proposer,
        _receiver: _dispute.disputer,
        _token: _params.bondToken,
        _amount: _params.bondSize
      });

      IOracle.Response memory _newResponse = IOracle.Response({
        requestId: _dispute.requestId,
        proposer: _dispute.disputer,
        response: _correctResponses[_dispute.requestId]
      });

      emit DisputeStatusChanged({_disputeId: _disputeId, _dispute: _dispute, _status: IOracle.DisputeStatus.Won});

      ORACLE.proposeResponse(_request, _newResponse);
      ORACLE.finalize(_request, _newResponse);
    } else {
      emit DisputeStatusChanged({_disputeId: _disputeId, _dispute: _dispute, _status: IOracle.DisputeStatus.Lost});

      ORACLE.finalize(_request, _response);
    }

    delete _correctResponses[_dispute.requestId];
  }

  /// @inheritdoc ICircuitResolverModule
  function disputeResponse(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external onlyOracle {
    RequestParameters memory _params = decodeRequestData(_request.disputeModuleData);

    (bool _success, bytes memory _correctResponse) = _params.verifier.call(_params.callData);

    if (!_success) revert CircuitResolverModule_VerificationFailed();

    _correctResponses[_response.requestId] = _correctResponse;

    IOracle.DisputeStatus _status = _response.response.length != _correctResponse.length
      || keccak256(_response.response) != keccak256(_correctResponse)
      ? IOracle.DisputeStatus.Won
      : IOracle.DisputeStatus.Lost;

    emit ResponseDisputed({
      _requestId: _response.requestId,
      _responseId: _dispute.responseId,
      _disputeId: _getId(_dispute),
      _dispute: _dispute,
      _blockNumber: block.number
    });

    ORACLE.updateDisputeStatus(_request, _response, _dispute, _status);
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
      && _params.bondSize != 0 && address(_params.verifier) != address(0) && _params.callData.length != 0;
  }
}
