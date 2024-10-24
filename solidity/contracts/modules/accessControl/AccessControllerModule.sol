// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AccessController} from '@defi-wonderland/prophet-core/solidity/contracts/AccessController.sol';
import {Module} from '@defi-wonderland/prophet-core/solidity/contracts/Module.sol';
import {IOracle} from '@defi-wonderland/prophet-core/solidity/interfaces/IOracle.sol';

abstract contract AccessControllerModule is AccessController, Module {
  constructor(IOracle _oracle) Module(_oracle) {}
}
