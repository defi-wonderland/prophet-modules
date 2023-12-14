// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// solhint-disable-next-line no-unused-import
import {IModule, Module} from '@defi-wonderland/prophet-core-contracts/solidity/contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';

import {IRootVerificationModule} from '../../../interfaces/modules/dispute/IRootVerificationModule.sol';
import {MerkleLib} from '../../libraries/MerkleLib.sol';

contract RootVerificationModule is Module, IRootVerificationModule {
  using MerkleLib for MerkleLib.Tree;

  /**
   * @notice The calculated correct root for a given request
   */
  mapping(bytes32 _requestId => bytes32 _correctRoot) internal _correctRoots;

  constructor(IOracle _oracle) Module(_oracle) {}

  /// @inheritdoc IModule
  function moduleName() external pure returns (string memory _moduleName) {
    return 'RootVerificationModule';
  }

  /// @inheritdoc IRootVerificationModule
  function decodeRequestData(bytes calldata _data) public pure returns (RequestParameters memory _params) {
    _params = abi.decode(_data, (RequestParameters));
  }

  /// @inheritdoc IRootVerificationModule
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
        response: abi.encode(_correctRoots[_dispute.requestId])
      });

      emit DisputeStatusChanged({_disputeId: _disputeId, _dispute: _dispute, _status: IOracle.DisputeStatus.Won});

      ORACLE.proposeResponse(_request, _newResponse);
      ORACLE.finalize(_request, _newResponse);
    } else {
      emit DisputeStatusChanged({_disputeId: _disputeId, _dispute: _dispute, _status: IOracle.DisputeStatus.Lost});
      ORACLE.finalize(_request, _response);
    }

    delete _correctRoots[_dispute.requestId];
  }

  /// @inheritdoc IRootVerificationModule
  function disputeResponse(
    IOracle.Request calldata _request,
    IOracle.Response calldata _response,
    IOracle.Dispute calldata _dispute
  ) external onlyOracle {
    RequestParameters memory _params = decodeRequestData(_request.disputeModuleData);

    bytes32 _correctRoot = _params.treeVerifier.calculateRoot(_params.treeData, _params.leavesToInsert);
    _correctRoots[_response.requestId] = _correctRoot;

    IOracle.DisputeStatus _status =
      abi.decode(_response.response, (bytes32)) != _correctRoot ? IOracle.DisputeStatus.Won : IOracle.DisputeStatus.Lost;

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
    _valid = (
      address(_params.accountingExtension) == address(0) || address(_params.bondToken) == address(0)
        || address(_params.treeVerifier) == address(0) || _params.bondSize == 0 || _params.treeData.length == 0
        || _params.leavesToInsert.length == 0
    ) ? false : true;
  }
}
