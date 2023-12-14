// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// solhint-disable-next-line no-unused-import
import {IModule, Module} from '@defi-wonderland/prophet-core-contracts/solidity/contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core-contracts/solidity/interfaces/IOracle.sol';

import {IBondedDisputeModule} from '../../../interfaces/modules/dispute/IBondedDisputeModule.sol';

contract BondedDisputeModule is Module, IBondedDisputeModule {
  constructor(IOracle _oracle) Module(_oracle) {}

  /// @inheritdoc IModule
  function moduleName() external pure returns (string memory _moduleName) {
    return 'BondedDisputeModule';
  }

  /// @inheritdoc IBondedDisputeModule
  function decodeRequestData(bytes calldata _data) public pure returns (RequestParameters memory _params) {
    _params = abi.decode(_data, (RequestParameters));
  }

  /// @inheritdoc IBondedDisputeModule
  function disputeResponse(
    IOracle.Request calldata _request,
    IOracle.Response calldata, /* _response */
    IOracle.Dispute calldata _dispute
  ) external onlyOracle {
    RequestParameters memory _params = decodeRequestData(_request.disputeModuleData);

    _params.accountingExtension.bond({
      _bonder: _dispute.disputer,
      _requestId: _dispute.requestId,
      _token: _params.bondToken,
      _amount: _params.bondSize
    });

    emit ResponseDisputed({
      _requestId: _dispute.requestId,
      _responseId: _dispute.responseId,
      _disputeId: _getId(_dispute),
      _dispute: _dispute,
      _blockNumber: block.number
    });
  }

  /// @inheritdoc IBondedDisputeModule
  function onDisputeStatusChange(
    bytes32 _disputeId,
    IOracle.Request calldata _request,
    IOracle.Response calldata, /* _response */
    IOracle.Dispute calldata _dispute
  ) external onlyOracle {
    RequestParameters memory _params = decodeRequestData(_request.disputeModuleData);
    IOracle.DisputeStatus _status = ORACLE.disputeStatus(_disputeId);

    if (_status == IOracle.DisputeStatus.NoResolution) {
      // No resolution, we release both bonds
      _params.accountingExtension.release({
        _bonder: _dispute.disputer,
        _requestId: _dispute.requestId,
        _token: _params.bondToken,
        _amount: _params.bondSize
      });

      _params.accountingExtension.release({
        _bonder: _dispute.proposer,
        _requestId: _dispute.requestId,
        _token: _params.bondToken,
        _amount: _params.bondSize
      });
    } else if (_status == IOracle.DisputeStatus.Won) {
      // Disputer won, we pay the disputer and release their bond
      _params.accountingExtension.pay({
        _requestId: _dispute.requestId,
        _payer: _dispute.proposer,
        _receiver: _dispute.disputer,
        _token: _params.bondToken,
        _amount: _params.bondSize
      });
      _params.accountingExtension.release({
        _bonder: _dispute.disputer,
        _requestId: _dispute.requestId,
        _token: _params.bondToken,
        _amount: _params.bondSize
      });
    } else if (_status == IOracle.DisputeStatus.Lost) {
      // Disputer lost, we pay the proposer and release their bond
      _params.accountingExtension.pay({
        _requestId: _dispute.requestId,
        _payer: _dispute.disputer,
        _receiver: _dispute.proposer,
        _token: _params.bondToken,
        _amount: _params.bondSize
      });
      _params.accountingExtension.release({
        _bonder: _dispute.proposer,
        _requestId: _dispute.requestId,
        _token: _params.bondToken,
        _amount: _params.bondSize
      });
    }

    emit DisputeStatusChanged({_disputeId: _disputeId, _dispute: _dispute, _status: _status});
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
        || _params.bondSize == 0
    ) ? false : true;
  }
}
