// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Script.sol";

import "../contracts/deployer.sol";
import "../contracts/marketplace.sol";

contract DeployScript is Script {
    uint256 public constant callbackGasLimit = 1_000_000; // TODO: TBD
    uint8 public constant failureHandleStrategy = 0; // BlockOnFail
    uint256 public constant tax = 100; // 1%

    address public operator;

    address public crossChain;
    address public groupHub;
    address public initOwner;
    address public fundWallet;

    function setUp() public {
        uint256 privateKey = uint256(vm.envBytes32("OP_PRIVATE_KEY"));
        operator = vm.addr(privateKey);
        console.log("operator balance: %s", operator.balance / 1e18);

        privateKey = uint256(vm.envBytes32("OWNER_PRIVATE_KEY"));
        initOwner = vm.addr(privateKey);
        fundWallet = initOwner;
        console.log("init owner: %s", initOwner);
    }

    function run() public {
        vm.startBroadcast(operator);
        Deployer deployer = new Deployer();
        console.log("deployer address: %s", address(deployer));
        Marketplace marketplace = new Marketplace();
        console.log("implMarketplace address: %s", address(marketplace));

        address proxyAdmin = deployer.calcCreateAddress(address(deployer), uint8(1));
        require(proxyAdmin == deployer.proxyAdmin(), "wrong proxyAdmin address");
        console.log("proxyAdmin address: %s", proxyAdmin);
        address proxyMarketplace = deployer.calcCreateAddress(address(deployer), uint8(2));
        require(proxyMarketplace == deployer.proxyMarketplace(), "wrong proxyMarketplace address");
        console.log("proxyMarketplace address: %s", proxyMarketplace);

        deployer.deploy(address(marketplace), initOwner, fundWallet, tax, callbackGasLimit, failureHandleStrategy);
        vm.stopBroadcast();
    }
}
