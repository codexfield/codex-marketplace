# greenfield-data-marketplace-contracts

Greenfield-data-marketplace is a marketplace protocol for safely and efficiently buying and selling data uploaded in [Greenfield](https://github.com/bnb-chain/greenfield-contracts).

## Install

To install dependencies:

```bash
git clone --recurse-submodules https://github.com/bnb-chain/data-marketplace-contracts.git && cd greenfield-contracts
yarn install
forge install
```

## Deploy

1. Copy `.env.example` and setup `OP_PRIVATE_KEY` and `OWNER_PRIVATE_KEY` in `.env`.

```bash
cp .env.example .env
```

2. Deploy with foundry.

```bash
forge script ./script/1-deploy.s.sol --rpc-url ${RPC_LOCAL} --legacy --broadcast --private-key ${OP_PRIVATE_KEY}
```

## Test

Test with foundry after deploying:

```bash
forge test --rpc-url ${RPC_LOCAL}
```

## License
The data marketplace contracts (i.e. all code inside the `contracts` directory) are licensed under the
[GNU Affero General Public License v3.0](https://www.gnu.org/licenses/agpl-3.0.en.html), also
included in our repository in the `COPYING` file.

## Disclaimer
The software and related documentation are under active development, all subject to potential future change without notification and not ready for production use. The code and security audit have not been fully completed and not ready for any bug bounty. We advise you to be careful and experiment on the network at your own risk. Stay safe out there.
