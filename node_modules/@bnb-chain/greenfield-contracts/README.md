# Greenfield Contracts
Greenfield Contracts is the bridge between Greenfield and BSC for cross-chain communication.

## Overview
The Greenfield Blockchain provides a comprehensive set of resources that can be mirrored on the BNB Smart Chain (BSC).
This includes buckets, objects, and groups, which can be stored and managed on the BSC as non-fungible tokens (NFTs)
conforming to the ERC-721 standard.

A bucket is a logical container for storing objects in Greenfield. An object, on the other hand, is a fundamental unit
of storage in Greenfield that represents a file consisting of data and its associated metadata.
Lastly, a group is a collection of accounts with the same permissions.

These resources can be mirrored on the BSC as ERC-721 NFTs, along with the members within a group, which represent
permissions to specify resources, that can be mirrored as ERC-1155 token. At present, the NFTs are not transferable,
but the transferability feature will be added in the near future.

Once these resources are mirrored on BSC, they can be directly managed by smart contracts on BSC.
These operations will directly affect the storage format, access permissions, and other aspects of the data on greenfield.
In other words, any changes made to the decentralized application on BSC will also reflect changes on Greenfield.
This integration between Greenfield Blockchain and BNB Smart Chain allows for greater flexibility and accessibility
when it comes to accessing and manipulating data, ultimately leading to a more streamlined and efficient
data management process.

## Key Contract
1. **CrossChain**. The underlying cross-chain communication protocol. This contract is responsible for handling
   all aspects of cross-chain communication packages, including verification, encoding, decoding, routing, reward distribution.
2. **GovHub**. This contract oversees all aspects of contract upgrades, parameter adjustments, and handles governance
   requests originating from the `Greenfield`. Additionally, it validates and executes governance proposals as required.
3. **TokenHub**. This contract is tasked with handling cross-chain transactions, encompassing both `transferIn` and
   `transferOut`. Upon initiating a cross-chain transfer from the `Greenfield` to the BSC, tokens are initially locked within
   the `TokenHub`, subsequently triggering a cross-chain transfer event.
4. **GroupHub**. This contract is responsible for managing the `Greenfield` group,
   including the addition and removal of members.
5. **BucketHub**. This contract is responsible for managing the `Greenfield` buckets.
6. **ObjectHub**. This contract is responsible for managing the `Greenfield` objects.

## Resource Operating Primitives
A number of cross-chain primitives have been defined on BSC to enable developers to manage greenfield resources on the
BSC directly, without the need for intermediaries.

**BNB**:
- transfer BNB bidirectionally between BSC and Greenfield

**Bucket**:
- create a bucket on BSC
- delete a bucket on BSC
- mirror bucket from Greenfield to BSC

**Object**:
- delete an object on BSC
- mirror object from Greenfield to BSC
- grant/revoke permissions of objects on BSC to accounts/groups
- create an object on BSC (pending)
- copy objects on BSC (pending)
- Kick off the execution of an object on BSC (pending)

**Group**:
- create a group on BSC
- delete a group on BSC
- change group members on BSC
- mirror group from Greenfield to BSC

Users can also approve smart contracts to operate the aforementioned resources instead, check the
[design](https://greenfield.bnbchain.org/docs/guide/dapp/permisson-control.html) for more details.



## Requirement

set environment
```shell
# require Node.js 14+
cp .env.example .env
# modify the env variable `DeployerPrivateKey` to your own private key

# make sure the address corresponding to the private key has enough tBNB in the BSC Testnet
```

Install foundry:
```shell script
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Install dependencies:
```shell
make install-dependencies
```

## Lint
```shell
yarn lint:check
yarn lint:write
```

## Build
```shell
make build
```

## Deploy
```shell
# modify the env variable `DeployerPrivateKey` to your own private key on BSC Testnet
npm run deploy:testnet

# modify the env variable `DeployerPrivateKey` to your own private key on BSC
npm run deploy:bsc
```

## Deployment
### Greenfield Contracts on BSC Testnet
- BSC Testnet ChainID: 97
- BSC Testnet RPC: https://data-seed-prebsc-1-s1.binance.org:8545/
- BSC Testnet Explorer: https://testnet.bscscan.com/

- Greenfield ChainID: greenfield_5600-1
- Greenfield Tendermint RPC: https://gnfd-testnet-fullnode-tendermint-us.bnbchain.org
- Greenfield GRPC swagger: https://gnfd-testnet-fullnode-tendermint-us.bnbchain.org/openapi
- Greenfield EthAPI: https://gnfd-testnet-fullnode-tendermint-us.bnbchain.org
- Greenfield Storage dApp: https://dcellar.io/
- Greenfield Explorer: http://greenfieldscan.com/

## Contract Entrypoint

### Testnet

| contract name | address                                    |
|---------------|--------------------------------------------|
| CrossChain    | 0x93Cf63F9Db8F2B6614Bf507eAaeb29c4D1EfA388 |
| TokenHub      | 0x8B7161A47f7eB5d16Cef291Ba320d4C499a9E51A |
| BucketHub     | 0xFAdD8F4081E64Ff3950f5831A83d7Be8D65Df5f4 |
| ObjectHub     | 0xcae1547e838aFe97585d5e661272D5aF228bE560 |
| GroupHub      | 0x28BCd1062dFc8fa6Ab3CA685C48A0e18ddBf1dBf |

Extra:

| contract name | address                                    |
|---------------|--------------------------------------------|
| Deployer      | 0xe1f7b4A7729fdb84D62901ba318cdDB6Cc490431 |
| ProxyAdmin    | 0xe67e17b18404002c8faF56087F7eA7e2D7CbFCf1 |
| LightClient   | 0x7Df5f0536E008E1Dd073Eb3d623D9fd476a6EBc0 |
| RelayerHub    | 0x701F1f576E1236EC7d607F32c7e5395E9856B7D6 |

## Verify on BSCScan
```shell
# modify the env variable `BSCSCAN_APIKEY` to your own api-key created on https://bscscan.com/myapikey
npm run verify:testnet
npm run verify:bsc
```

## Cross-Chain Transfer to GreenField
```shell
# make sure the foundry dependency are installed 
# 1. add private-key, receiver and BNB amount to ./foundry-scripts/transferOut.sh
# 2. run shell command
# cross-chain transfer 0.2 BNB (amount = 2 * 10 ^ 17) to your receiver on GreenField
forge script foundry-scripts/TokenHub.s.sol:TokenHubScript \
--private-key ${your private key} \
--sig "transferOut(address receiver, uint256 amount)" \
${the receiver you transfer to} 200000000000000000  \
-f https://data-seed-prebsc-1-s1.binance.org:8545/  \
--legacy --ffi --broadcast
# More examples please refer to ./foundry-scripts/examples/transferOut.sh
```

## Cross-Chain Operation to GreenField
```shell
# make sure the foundry dependency are installed 
# group operation - add member to the group
forge script foundry-scripts/GroupHub.s.sol:GroupHubScript \
--private-key ${your private key} \
--sig "addMember(address operator, uint256 groupId, address member)" \
${the owner of the group} ${your group id} ${the member address to add} \
-f https://data-seed-prebsc-1-s1.binance.org:8545/ \
--legacy --ffi --broadcast
# More examples please refer to ./foundry-scripts/examples/updateGroup.sh

# bucket operation - delete a bucket
forge script foundry-scripts/BucketHub.s.sol:BucketHubScript \
--private-key ${your private key} \
--sig "deleteBucket(uint256 bucketId)" \
${bucketId to delete} \
-f https://data-seed-prebsc-1-s1.binance.org:8545/ \
--legacy --ffi --broadcast
# More examples please refer to ./foundry-scripts/examples/bucketHub.sh

# object operation - delete an object
forge script foundry-scripts/ObjectHub.s.sol:ObjectHubScript \
--private-key ${your private key} \
--sig "deleteObject(uint256 id)" \
${object id to delete} \
-f https://data-seed-prebsc-1-s1.binance.org:8545/ \
--legacy --ffi --broadcast
```

## Inspect Transactions
```shell
# 1. add your txHash to `InspectTxHashes` on `scripts/3-decode-events.ts`
# 2. run script on BSC testnet
npx hardhat run scripts/3-decode-events.ts --network bsc-testnet

# run script on BSC
npx hardhat run scripts/3-decode-events.ts --network bsc
```

## Test
```shell
# start a local chain
anvil -b 1

# run test on another terminal
npm run deploy:local
forge t -vvv --ffi
```


## Large Transfer Unlock
```shell script
npm install typescript ts-node -g

cp .env.example .env
# set RPC_URL, OPERATOR_PRIVATE_KEY, UNLOCK_RECEIVER to .env

ts-node scripts/6-claim-unlock-bot.ts
```

## Disclaimer
**The software and related documentation are under active development, all subject to potential future change without
notification and not ready for production use. The code and security audit have not been fully completed and not ready
for any bug bounty. We advise you to be careful and experiment on the network at your own risk. Stay safe out there.**

## Contribution
Thank you for considering helping with the source code! We appreciate contributions from anyone on the internet, no
matter how small the fix may be.

If you would like to contribute to Greenfield, please follow these steps: fork the project, make your changes, commit them,
and send a pull request to the maintainers for review and merge into the main codebase. However, if you plan on submitting
more complex changes, we recommend checking with the core developers first via GitHub issues (we will soon have a Discord channel)
to ensure that your changes align with the project's general philosophy. This can also help reduce the workload of both
parties and streamline the review and merge process.

## License
The greenfield contracts (i.e. all code inside the `contracts` directory) are licensed under the
[GNU Affero General Public License v3.0](https://www.gnu.org/licenses/agpl-3.0.en.html), also
included in our repository in the `COPYING` file.
