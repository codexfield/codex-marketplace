// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../contracts/interface/IMarketplace.sol";
import {Marketplace} from "../contracts/Marketplace.sol";

contract UpgradeScript is Script {
    address public operator;

    address public crossChain;
    address public groupHub;
    address public initOwner;
    address public fundWallet;

    address public proxyAdmin;
    address public proxyMarketPlace;

    function setUp() public {
        uint256 privateKey = uint256(vm.envBytes32("OP_PRIVATE_KEY"));
        operator = vm.addr(privateKey);
        console.log("operator balance: %s", operator.balance / 1e18);

        privateKey = uint256(vm.envBytes32("OWNER_PRIVATE_KEY"));
        initOwner = vm.addr(privateKey);
        console.log("init owner: %s", initOwner);

        proxyAdmin = vm.envAddress("PROXY_ADMIN");
        console.log("proxyAdmin address: %s", proxyAdmin);

        proxyMarketPlace = vm.envAddress("PROXY_MP");
        console.log("proxyMarketPlace address: %s", proxyMarketPlace);
    }

    function run() public {
        vm.startBroadcast(initOwner);
        Marketplace newImpl = new Marketplace();
        require(address(newImpl) != proxyMarketPlace, "same impl address");

        (uint256 oldVersion,,) = IMarketplace(proxyMarketPlace).versionInfo();
        (uint256 newVersion,,) = newImpl.versionInfo();
        require(oldVersion < newVersion, "new version must be greater than old version");
        ProxyAdmin(proxyAdmin).upgrade(ITransparentUpgradeableProxy(proxyMarketPlace), address(newImpl));
        vm.stopBroadcast();

        console.log("new implMarketPlace address: %s", address(newImpl));
    }
}
