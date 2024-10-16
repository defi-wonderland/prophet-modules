// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from 'forge-std/Script.sol';

import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';
import {IResolutionModule} from
  '@defi-wonderland/prophet-core/solidity/interfaces/modules/resolution/IResolutionModule.sol';

import {BondEscalationModule} from '../contracts/modules/dispute/BondEscalationModule.sol';
import {BondedDisputeModule} from '../contracts/modules/dispute/BondedDisputeModule.sol';

import {CircuitResolverModule} from '../contracts/modules/dispute/CircuitResolverModule.sol';
import {RootVerificationModule} from '../contracts/modules/dispute/RootVerificationModule.sol';
import {CallbackModule} from '../contracts/modules/finality/CallbackModule.sol';
import {MultipleCallbacksModule} from '../contracts/modules/finality/MultipleCallbacksModule.sol';
import {ContractCallRequestModule} from '../contracts/modules/request/ContractCallRequestModule.sol';
import {HttpRequestModule} from '../contracts/modules/request/HttpRequestModule.sol';

import {SparseMerkleTreeRequestModule} from '../contracts/modules/request/SparseMerkleTreeRequestModule.sol';
import {ArbitratorModule} from '../contracts/modules/resolution/ArbitratorModule.sol';
import {BondEscalationResolutionModule} from '../contracts/modules/resolution/BondEscalationResolutionModule.sol';
import {ERC20ResolutionModule} from '../contracts/modules/resolution/ERC20ResolutionModule.sol';
import {PrivateERC20ResolutionModule} from '../contracts/modules/resolution/PrivateERC20ResolutionModule.sol';
import {BondedResponseModule} from '../contracts/modules/response/BondedResponseModule.sol';

import {AccountingExtension} from '../contracts/extensions/AccountingExtension.sol';
import {BondEscalationAccounting} from '../contracts/extensions/BondEscalationAccounting.sol';

// solhint-disable no-console
contract Deploy is Script {
  // Oracle
  IOracle oracle = IOracle(0xe40DED509A3806Eed8065b478BB681953bD9B554);

  // Request modules
  HttpRequestModule httpRequestModule;
  ContractCallRequestModule contractCallRequestModule;
  SparseMerkleTreeRequestModule sparseMerkleTreeRequestModule;

  // Response modules
  BondedResponseModule bondedResponseModule;

  // Dispute modules
  BondedDisputeModule bondedDisputeModule;
  BondEscalationModule bondEscalationModule;
  RootVerificationModule rootVerificationModule;
  CircuitResolverModule circuitResolverModule;

  // Resolution modules
  ArbitratorModule arbitratorModule;
  ERC20ResolutionModule erc20ResolutionModule;
  PrivateERC20ResolutionModule privateErc20ResolutionModule;
  BondEscalationResolutionModule bondEscalationResolutionModule;

  // Finality modules
  CallbackModule callbackModule;
  MultipleCallbacksModule multipleCallbacksModule;

  // Extensions
  AccountingExtension accountingExtension;
  BondEscalationAccounting bondEscalationAccounting;

  function run() public {
    address deployer = vm.rememberKey(vm.envUint('DEPLOYER_PRIVATE_KEY'));

    vm.startBroadcast(deployer);

    // Deploy oracle
    console.log('ORACLE:', address(oracle));

    // Deploy arbitrator module
    arbitratorModule = new ArbitratorModule(oracle);
    console.log('ARBITRATOR_MODULE:', address(arbitratorModule));

    // Deploy bonded dispute module
    bondedDisputeModule = new BondedDisputeModule(oracle);
    console.log('BONDED_DISPUTE_MODULE:', address(bondedDisputeModule));

    // Deploy bonded response module
    bondedResponseModule = new BondedResponseModule(oracle);
    console.log('BONDED_RESPONSE_MODULE:', address(bondedResponseModule));

    // Deploy bond escalation module
    bondEscalationModule = new BondEscalationModule(oracle);
    console.log('BOND_ESCALATION_MODULE:', address(bondEscalationModule));

    // Deploy callback module
    callbackModule = new CallbackModule(oracle);
    console.log('CALLBACK_MODULE:', address(callbackModule));

    // Deploy http request module
    httpRequestModule = new HttpRequestModule(oracle);
    console.log('HTTP_REQUEST_MODULE:', address(httpRequestModule));

    // Deploy contract call module
    contractCallRequestModule = new ContractCallRequestModule(oracle);
    console.log('CONTRACT_CALL_MODULE:', address(contractCallRequestModule));

    // Deploy ERC20 resolution module
    erc20ResolutionModule = new ERC20ResolutionModule(oracle);
    console.log('ERC20_RESOLUTION_MODULE:', address(erc20ResolutionModule));

    // Deploy private ERC20 resolution module
    privateErc20ResolutionModule = new PrivateERC20ResolutionModule(oracle);
    console.log('PRIVATE_ERC20_RESOLUTION_MODULE:', address(privateErc20ResolutionModule));

    // Deploy bond escalation resolution module
    bondEscalationResolutionModule = new BondEscalationResolutionModule(oracle);
    console.log('BOND_ESCALATION_RESOLUTION_MODULE:', address(bondEscalationResolutionModule));

    // Deploy multiple callbacks module
    multipleCallbacksModule = new MultipleCallbacksModule(oracle);
    console.log('MULTIPLE_CALLBACKS_MODULE:', address(multipleCallbacksModule));

    // Deploy root verification module
    rootVerificationModule = new RootVerificationModule(oracle);
    console.log('ROOT_VERIFICATION_MODULE:', address(rootVerificationModule));

    // Deploy root verification module
    sparseMerkleTreeRequestModule = new SparseMerkleTreeRequestModule(oracle);
    console.log('SPARSE_MERKLE_TREE_REQUEST_MODULE:', address(sparseMerkleTreeRequestModule));

    // Deploy accounting extension
    accountingExtension = new AccountingExtension(oracle);
    console.log('ACCOUNTING_EXTENSION:', address(accountingExtension));

    // Deploy bond escalation accounting
    address[] memory authorizedCallers = new address[](1);
    authorizedCallers[0] = address(bondEscalationModule);
    bondEscalationAccounting = new BondEscalationAccounting(oracle, authorizedCallers);
    console.log('BOND_ESCALATION_ACCOUNTING_EXTENSION:', address(bondEscalationAccounting));

    // Deploy circuit resolver module
    circuitResolverModule = new CircuitResolverModule(oracle);
    console.log('CIRCUIT_RESOLVER_MODULE:', address(circuitResolverModule));
  }
}
