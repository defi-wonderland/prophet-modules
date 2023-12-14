# Contract Call Request Module

See [IContractCallRequestModule.sol](/solidity/interfaces/modules/request/IContractCallRequestModule.sol/interface.IContractCallRequestModule.md) for more details.

## 1. Introduction

The `ContractCallRequestModule` is a module for requesting on-chain information. It specifies the source and the reward for a correct response.

## 2. Contract Details

### Key Methods

- `decodeRequestData`: Decodes request parameters. It returns the target contract address, the function selector, the encoded arguments of the function to call, the accounting extension to bond and release funds, the payment token, and the payment amount.
- `createRequest`: Can be used to bond the requester's funds and validate the request parameters.
- `finalizeRequest`: Finalizes a request by paying the proposer if there is a valid response, or releasing the requester's bond if no valid response was provided.

### Request Parameters

- `target`: The address of the contract to get the response from.
- `functionSelector`: The function that returns the response to the request.
- `data`: The data to pass to the function.
- `accountingExtension`: The address holding the bonded tokens. It must implement the [IAccountingExtension.sol](/solidity/interfaces/extensions/IAccountingExtension.sol/interface.IAccountingExtension.md) interface.
- `paymentToken`: The ERC20 token used for paying the proposer.
- `paymentAmount`: The amount of tokens the proposer will receive for a correct response.

## 3. Key Mechanisms & Concepts

- Check out [Accounting Extension](../../extensions/accounting.md).

## 4. Gotchas

- The proposers must keep a list of allowed targets and function selectors and only interact with the contracts they trust. One obvious trick is to use `transfer` as the function to call, which would allow the requester to steal the proposer's funds.
- Misconfiguring the data or choosing a function that does not exist on the target would render the request impossible to answer.
