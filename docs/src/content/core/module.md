# Module

See [IModule.sol](/solidity/interfaces/core/IModule.sol/interface.IModule.md) for more details.

`Module` is an abstract contract that defines common functions and modifiers. A module is supposed to inherit the abstract contract and implement specific logic in one of the hooks, for example `finalizeRequest`. All public functions in the contract are callable only by the oracle, and there are internal functions ensuring the integrity of the data being passed around, such as `_validateResponse` and `_validateDispute`.

In addition to the abstract contact, we've created interfaces for each type of module:
- [IRequestModule](/solidity/interfaces/core/modules/request/IRequestModule.sol/interface.IRequestModule.md)
- [IResponseModule](/solidity/interfaces/core/modules/response/IResponseModule.sol/interface.IResponseModule.md)
- [IDisputeModule](/solidity/interfaces/core/modules/dispute/IDisputeModule.sol/interface.IDisputeModule.md)
- [IResolutionModule](/solidity/interfaces/core/modules/resolution/IResolutionModule.sol/interface.IResolutionModule.md)
- [IFinalityModule](/solidity/interfaces/core/modules/finality/IFinalityModule.sol/interface.IFinalityModule.md)

Each of them inherits the `IModule` interface and adds additional functions specific to the module type.
