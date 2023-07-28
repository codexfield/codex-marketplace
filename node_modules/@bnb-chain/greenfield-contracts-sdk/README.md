## Overview

This document provides an overview of the Greenfield Contracts SDK, a library of smart contracts for the bnb-chain. 
The SDK enables developers to quickly and easily integrate contracts into their decentralized applications.

### Installation

```console
$ npm install @bnb-chain/greenfield-contracts-sdk
```

Alternatively, you can obtain the contracts directly from the [GitHub repository](https://github.com/bnb-chain/greenfield-contracts-sdk). 
When doing so, ensure that you specify the appropriate release, such as `v1.0.0`, instead of using the `main` branch.

### Usage

After installing the library, import the desired contracts as follows:

```solidity
pragma solidity ^0.8.0;

import "@bnb-chain/greenfield-contracts-sdk/BucketApp.sol";

contract MyDapp is BucketApp {
}
```

For security purposes, always use the installed code without modifications. Do not copy-paste code from online sources or modify it yourself. 

## Learn More
- [The Cross-Chain Programmability on Greenfield](https://greenfield.bnbchain.org/docs/guide/concept/programmability.html)
- [Resource Mirror on Greenfield](https://greenfield.bnbchain.org/docs/guide/dapp/overview.html#resource-mirror)
- [Quick Start Building Smart Contract on Greenfield](https://greenfield.bnbchain.org/docs/guide/dapp/quick-start.html)

## Disclaimer
The software and related documentation are under active development, all subject to potential future change without 
notification and not ready for production use. The code and security audit have not been fully completed and not 
ready for any bug bounty. We advise you to be careful and experiment on the network at your own risk. 

Stay safe out there.

## Contribute
Thank you for expressing your willingness to contribute to the Greenfield source code. We deeply appreciate any help, no matter how small the fix. We welcome contributions from anyone on the internet, and we value your input.

If you're interested in contributing to Greenfield, please follow these steps:

Fork the project on GitHub.
Fix the issue.
Commit the changes.
Send a pull request for the maintainers to review and merge into the main codebase.

## License

The greenfield contract binaries is licensed under the
[GNU Affero General Public License v3.0](https://www.gnu.org/licenses/agpl-3.0.en.html), also
included in our repository in the `COPYING` file.
