# Modules

Here you can find the list and the details of each module available in Prophet
- [Request](./request.md)
- [Response](./response.md)
- [Dispute](./dispute.md)
- [Resolution](./resolution.md)
- [Finality](./finality.md)

## Common Parts

You can notice that many modules follow the same structure. This is because they all inherit from the `IModule` interface which defines the common functions and modifiers that all modules should have.

- `moduleName` is required to properly show the module in Prophet UI.
- `RequestParameters` is which parameters are required for the request to be processed with the module.
- `decodeRequestData` decodes the ABI encoded parameters using the `RequestParameters` struct and returns them as a list. This is useful for both on-chain and off-chain components.

## Best Practices

When building a module, keep in mind these tips to make the module predictable and easier to work with:

1. Always process the release and refund of the bond within the same module where the bonding initially occurs. This approach enhances composability and allows developers to concentrate on the logic specific to their module.
1. Typically, a module is designed to function independently. However, there are instances where multiple modules are developed in a manner that necessitates their joint use. For an example take a look at [SparseMerkleTreeModule](./request/sparse_merkle_tree_request_module.md) and [RootVerificationModule](./dispute/root_verification_module.md).
1. When feasible, avoid requiring users to interact directly with the module. Instead, route all calls via the oracle.
