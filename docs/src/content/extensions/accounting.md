# Accounting Extension

See [IAccountingExtension.sol](/solidity/interfaces/extensions/IAccountingExtension.sol/interface.IAccountingExtension.md) for more details.

## 1. Introduction

The Accounting Extension is a contract that allows users to deposit and bond funds to be used for payments and disputes. It provides a way to manage user balances within the system, supporting frictionless interactions with the Oracle and the modules.

## 2. Contract Details

### Key Methods

- `deposit`: Allows a user to deposit a specific amount of a token into the accounting extension. If ETH is being deposited, it is wrapped to WETH.
- `withdraw`: By calling this function, a user can withdraw a specific amount of a token from the accounting extension.
- `bond`: Allows a user to lock a specific amount of a token for a specific request. The tokens stay in the accounting extension and will not be withdrawable until they are released by a module.
- `release`: Allows a module to release a specific amount of a token that was previously bonded to a request. The tokens will be moved back to the user's balance.
- `pay`: Transfers a specific amount of a bonded token from the payer to the receiver. This function can only be called by a module.

## 3. Key Mechanisms & Concepts

- **Deposits**: Users can deposit tokens into the Accounting Extension. These deposits are tracked in a mapping that associates each user's address with their balance of each token. Deposits can be made in any ERC20 token, including wrapped Ether (WETH).

- **Withdrawals**: Users can withdraw their deposited tokens at any time, provided they have sufficient balance. The withdrawal operation reduces the user's balance in the Accounting Extension and transfers the tokens back to the user's address. Locked tokens can't be withdrawn until they're released by a module.

- **Bonding**: Users can lock their tokens up to be allowed to participate in a request. Tokens stay in the accounting extension but they cannot be withdrawn until the request is finalized or the tokens are released.

- **Payments**: The Accounting Extension allows for payments to be made from one user to another. This usually means rewards for correct proposers and disputers and slashing malicious actors. It's done by unlocking and transferring the bonded tokens from the payer to the receiver's balance. Payments can only be initiated by modules.

- **Releasing Bonds**: Bonds can be released by allowed modules, which moves the bonded tokens back to the user's balance, making them available for withdrawal or bonding to a different request.

## 4. Gotchas

- Before depositing ERC20 tokens, users must first approve the Accounting Extension to transfer the tokens on their behalf.
-  Users can only withdraw tokens that are not currently bonded. If a user has bonded tokens for a request, those tokens are locked until they are released by an allowed module. Attempting to withdraw bonded tokens will result in an error. Attempting to slash or pay out tokens that are not locked will also result in a transaction being reverted.
- The contract supports any ERC20 token, including wrapped Ether (WETH). However, if a user tries to deposit a non-ERC20 token or a token that the contract otherwise doesn't support, the transaction will fail.
