# Prophet Modules

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/defi-wonderland/prophet-modules/blob/main/LICENSE)

⚠️ The code has not been audited yet, tread with caution.

## Overview

Prophet presents a versatile and fully adaptable optimistic oracle solution, transcending the boundaries of conventional dispute resolution modules. With its emphasis on complete control and modularity across all aspects of the system, Prophet is an open-source public good for the Optimism community.

## Setup

This project uses [Foundry](https://book.getfoundry.sh/). To build it locally, run:

```sh
git clone git@github.com:defi-wonderland/prophet-modules.git
cd
yarn install
yarn build
```

### Available Commands

Make sure to set `OPTIMISM_RPC` environment variable before running end-to-end tests.

| Yarn Command              | Description                                                                                                                     |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `yarn build`              | Compile all contracts and export them as [a node package](https://www.npmjs.com/package/@defi-wonderland/prophet-modules-interfaces). |
| `yarn docs:build`         | Generate documentation with [`forge doc`](https://book.getfoundry.sh/reference/forge/forge-doc).                                |
| `yarn docs:run`           | Start the documentation server.                                                                                                 |
| `yarn test`               | Run all unit and integration tests.                                                                                             |
| `yarn test:unit`          | Run unit tests.                                                                                                                 |
| `yarn test:integration`   | Run integration tests.                                                                                                          |
| `yarn test:gas`           | Run all unit and integration tests, and make a gas report.                                                                      |

## Licensing

The primary license for Prophet contracts is MIT, see [`LICENSE`](./LICENSE).

## Contributors

Prophet was built with ❤️ by [Wonderland](https://defi.sucks).

Wonderland is a team of top Web3 researchers, developers, and operators who believe that the future needs to be open-source, permissionless, and decentralized.

[DeFi sucks](https://defi.sucks), but Wonderland is here to make it better.
