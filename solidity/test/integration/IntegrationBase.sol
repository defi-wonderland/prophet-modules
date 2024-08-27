// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// solhint-disable no-unused-import
// solhint-disable-next-line no-console
import {console} from 'forge-std/console.sol';

import {IOracle, Oracle} from '@defi-wonderland/prophet-core/solidity/contracts/Oracle.sol';
import {IDisputeModule} from '@defi-wonderland/prophet-core/solidity/interfaces/modules/dispute/IDisputeModule.sol';
import {IFinalityModule} from '@defi-wonderland/prophet-core/solidity/interfaces/modules/finality/IFinalityModule.sol';
import {IRequestModule} from '@defi-wonderland/prophet-core/solidity/interfaces/modules/request/IRequestModule.sol';
import {IResolutionModule} from
  '@defi-wonderland/prophet-core/solidity/interfaces/modules/resolution/IResolutionModule.sol';
import {IResponseModule} from '@defi-wonderland/prophet-core/solidity/interfaces/modules/response/IResponseModule.sol';
import {ValidatorLib} from '@defi-wonderland/prophet-core/solidity/libraries/ValidatorLib.sol';
import {DSTestPlus} from '@defi-wonderland/solidity-utils/solidity/test/DSTestPlus.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IWETH9} from '../utils/external/IWETH9.sol';

import {AccountingExtension, IAccountingExtension} from '../../contracts/extensions/AccountingExtension.sol';
import {
  BondEscalationAccounting, IBondEscalationAccounting
} from '../../contracts/extensions/BondEscalationAccounting.sol';
import {BondEscalationModule, IBondEscalationModule} from '../../contracts/modules/dispute/BondEscalationModule.sol';
import {BondedDisputeModule, IBondedDisputeModule} from '../../contracts/modules/dispute/BondedDisputeModule.sol';
import {
  IRootVerificationModule, RootVerificationModule
} from '../../contracts/modules/dispute/RootVerificationModule.sol';
import {CallbackModule, ICallbackModule} from '../../contracts/modules/finality/CallbackModule.sol';
import {HttpRequestModule, IHttpRequestModule} from '../../contracts/modules/request/HttpRequestModule.sol';
import {
  ISparseMerkleTreeRequestModule,
  SparseMerkleTreeRequestModule
} from '../../contracts/modules/request/SparseMerkleTreeRequestModule.sol';
import {ArbitratorModule, IArbitratorModule} from '../../contracts/modules/resolution/ArbitratorModule.sol';
import {BondedResponseModule, IBondedResponseModule} from '../../contracts/modules/response/BondedResponseModule.sol';
import {SparseMerkleTreeL32Verifier} from '../../contracts/periphery/SparseMerkleTreeL32Verifier.sol';

import {IArbitrator} from '../../interfaces/IArbitrator.sol';
import {IProphetCallback} from '../../interfaces/IProphetCallback.sol';
import {ITreeVerifier} from '../../interfaces/ITreeVerifier.sol';

import {MockArbitrator} from '../mocks/MockArbitrator.sol';
import {MockAtomicArbitrator} from '../mocks/MockAtomicArbitrator.sol';
import {MockCallback} from '../mocks/MockCallback.sol';

import {Helpers} from '../utils/Helpers.sol';
import {TestConstants} from '../utils/TestConstants.sol';
// solhint-enable no-unused-import

contract IntegrationBase is DSTestPlus, TestConstants, Helpers {
  uint256 public constant FORK_BLOCK = 122_612_760;

  uint256 internal _initialBalance = 100_000 ether;

  address public requester = makeAddr('requester');
  address public keeper = makeAddr('keeper');
  address public governance = makeAddr('governance');

  Oracle public oracle;
  HttpRequestModule internal _requestModule;
  BondedResponseModule internal _responseModule;
  AccountingExtension internal _accountingExtension;
  BondEscalationAccounting internal _bondEscalationAccounting;
  BondedDisputeModule internal _bondedDisputeModule;
  ArbitratorModule internal _arbitratorModule;
  CallbackModule internal _callbackModule;
  MockCallback internal _mockCallback;
  MockArbitrator internal _mockArbitrator;
  BondEscalationModule internal _bondEscalationModule;

  IERC20 public usdc = IERC20(label(USDC_ADDRESS, 'USDC'));
  IWETH9 public weth = IWETH9(label(WETH_ADDRESS, 'WETH'));

  string internal _expectedUrl = 'https://api.coingecko.com/api/v3/simple/price?';
  IHttpRequestModule.HttpMethod internal _expectedMethod = IHttpRequestModule.HttpMethod.GET;
  string internal _expectedBody = 'ids=ethereum&vs_currencies=usd';
  string internal _expectedResponse = '{"ethereum":{"usd":1000}}';
  uint256 internal _expectedBondSize = 100 ether;
  uint256 internal _expectedReward = 30 ether;
  uint256 internal _expectedDeadline;
  uint256 internal _expectedCallbackValue = 42;
  uint256 internal _baseDisputeWindow = 120; // blocks
  bytes32 internal _ipfsHash = bytes32('QmR4uiJH654k3Ta2uLLQ8r');
  uint256 internal _blocksDeadline = 600;

  function setUp() public virtual {
    vm.createSelectFork(vm.rpcUrl('optimism'), FORK_BLOCK);

    // Transfer some DAI and WETH to the users
    deal(address(weth), requester, _initialBalance);
    deal(address(usdc), requester, _initialBalance);

    deal(address(weth), proposer, _initialBalance);
    deal(address(usdc), proposer, _initialBalance);

    deal(address(weth), disputer, _initialBalance);
    deal(address(usdc), disputer, _initialBalance);

    // Deploy every contract needed
    vm.startPrank(governance);

    oracle = new Oracle();
    label(address(oracle), 'Oracle');

    _requestModule = new HttpRequestModule(oracle);
    label(address(_requestModule), 'RequestModule');

    _responseModule = new BondedResponseModule(oracle);
    label(address(_responseModule), 'ResponseModule');

    _bondedDisputeModule = new BondedDisputeModule(oracle);
    label(address(_bondedDisputeModule), 'DisputeModule');

    _arbitratorModule = new ArbitratorModule(oracle);
    label(address(_arbitratorModule), 'ResolutionModule');

    _callbackModule = new CallbackModule(oracle);
    label(address(_callbackModule), 'CallbackModule');

    _accountingExtension = new AccountingExtension(oracle);
    label(address(_accountingExtension), 'AccountingExtension');

    _bondEscalationModule = new BondEscalationModule(oracle);
    label(address(_bondEscalationModule), 'BondEscalationModule');

    _bondEscalationAccounting = new BondEscalationAccounting(oracle);
    label(address(_bondEscalationAccounting), 'BondEscalationAccounting');

    _mockCallback = new MockCallback();
    _mockArbitrator = new MockArbitrator();
    vm.stopPrank();

    // Set the expected deadline
    _expectedDeadline = block.number + _blocksDeadline;

    // Configure the mock request
    mockRequest.requestModuleData = abi.encode(
      IHttpRequestModule.RequestParameters({
        url: _expectedUrl,
        body: _expectedBody,
        method: _expectedMethod,
        accountingExtension: _accountingExtension,
        paymentToken: usdc,
        paymentAmount: _expectedReward
      })
    );

    mockRequest.responseModuleData = abi.encode(
      IBondedResponseModule.RequestParameters({
        accountingExtension: _accountingExtension,
        bondToken: usdc,
        bondSize: _expectedBondSize,
        deadline: _expectedDeadline,
        disputeWindow: _baseDisputeWindow
      })
    );

    mockRequest.disputeModuleData = abi.encode(
      IBondedDisputeModule.RequestParameters({
        accountingExtension: _accountingExtension,
        bondToken: usdc,
        bondSize: _expectedBondSize
      })
    );

    mockRequest.resolutionModuleData =
      abi.encode(IArbitratorModule.RequestParameters({arbitrator: address(_mockArbitrator)}));

    mockRequest.finalityModuleData = abi.encode(
      ICallbackModule.RequestParameters({target: address(_mockCallback), data: abi.encode(_expectedCallbackValue)})
    );

    mockRequest.requestModule = address(_requestModule);
    mockRequest.responseModule = address(_responseModule);
    mockRequest.disputeModule = address(_bondedDisputeModule);
    mockRequest.resolutionModule = address(_arbitratorModule);
    mockRequest.finalityModule = address(_callbackModule);
    mockRequest.requester = requester;
    mockRequest.nonce = uint96(oracle.totalRequestCount());

    _resetMockIds();
  }

  function _mineBlock() internal {
    _mineBlocks(1);
  }

  function _mineBlocks(uint256 _blocks) internal {
    vm.warp(block.timestamp + _blocks * BLOCK_TIME);
    vm.roll(block.number + _blocks);
  }

  /**
   * @notice Computes the IDs of the mock request, response and dispute and sets them in the mock objects
   */
  function _resetMockIds() internal {
    // Update the mock response
    mockResponse.requestId = _getId(mockRequest);

    // Update the mock dispute
    mockDispute.requestId = _getId(mockRequest);
    mockDispute.responseId = _getId(mockResponse);
  }

  /**
   * @notice Pranks the requester and creates a request
   * @dev The bond should be deposited into the accounting extension prior to calling this function
   */
  function _createRequest() internal returns (bytes32 _requestId) {
    vm.startPrank(requester);
    _accountingExtension.approveModule(address(_requestModule));
    _requestId = oracle.createRequest(mockRequest, _ipfsHash);
    vm.stopPrank();
  }

  /**
   * @notice Pranks the proposer and proposes a response
   * @dev The bond should be deposited into the accounting extension prior to calling this function
   */
  function _proposeResponse() internal returns (bytes32 _responseId) {
    vm.startPrank(proposer);
    _accountingExtension.approveModule(address(_responseModule));
    _responseId = oracle.proposeResponse(mockRequest, mockResponse);
    vm.stopPrank();
  }

  /**
   * @notice Pranks the disputer and disputes a response
   * @dev The bond should be deposited into the accounting extension prior to calling this function
   */
  function _disputeResponse() internal returns (bytes32 _disputeId) {
    vm.startPrank(disputer);
    _accountingExtension.approveModule(address(_bondedDisputeModule));
    _disputeId = oracle.disputeResponse(mockRequest, mockResponse, mockDispute);
    vm.stopPrank();
  }

  /**
   * @notice Deposits the specified amount of tokens to the accounting extension
   *
   * @param _accounting The accounting extension
   * @param _depositor The address of the depositor
   * @param _token The token to deposit
   * @param _amount The amount to deposit
   */
  function _deposit(IAccountingExtension _accounting, address _depositor, IERC20 _token, uint256 _amount) internal {
    if (_token.balanceOf(_depositor) < _amount) {
      deal(address(_token), _depositor, _amount);
    }

    vm.startPrank(_depositor);
    _token.approve(address(_accounting), _amount);
    _accounting.deposit(_token, _amount);
    vm.stopPrank();
  }
}
