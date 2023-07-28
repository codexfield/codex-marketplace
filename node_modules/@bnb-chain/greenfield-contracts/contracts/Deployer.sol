// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "./GnfdProxy.sol";
import "./GnfdProxyAdmin.sol";
import "./GnfdLightClient.sol";
import "./CrossChain.sol";
import "./RelayerHub.sol";
import "./middle-layer/GovHub.sol";
import "./middle-layer/TokenHub.sol";
import "./middle-layer/resource-mirror/BucketHub.sol";
import "./middle-layer/resource-mirror/ObjectHub.sol";
import "./middle-layer/resource-mirror/GroupHub.sol";

contract Deployer {
    uint16 public immutable gnfdChainId;

    address public immutable proxyAdmin;
    address public immutable proxyGovHub;
    address public immutable proxyCrossChain;
    address public immutable proxyTokenHub;
    address public immutable proxyLightClient;
    address public immutable proxyRelayerHub;
    address public immutable proxyBucketHub;
    address public immutable proxyObjectHub;
    address public immutable proxyGroupHub;

    bytes public initConsensusStateBytes;
    address public implGovHub;
    address public implCrossChain;
    address public implTokenHub;
    address public implLightClient;
    address public implRelayerHub;
    address public implBucketHub;
    address public implObjectHub;
    address public implGroupHub;
    address public addBucketHub;
    address public addObjectHub;
    address public addGroupHub;
    address public bucketToken;
    address public objectToken;
    address public groupToken;
    address public memberToken;
    address public bucketRlp;
    address public objectRlp;
    address public groupRlp;

    bool public deployed;

    constructor(uint16 _gnfdChainId) {
        gnfdChainId = _gnfdChainId;

        /*
            @dev deploy workflow
            a. Generate contracts addresses in advance first while deploy `Deployer`
            b. Write the generated proxy addresses to `Config` contract constants by JS script
            c. Deploy the proxy contracts, checking if they are equal to the generated addresses before
        */
        proxyAdmin = calcCreateAddress(address(this), uint8(1));
        proxyGovHub = calcCreateAddress(address(this), uint8(2));
        proxyCrossChain = calcCreateAddress(address(this), uint8(3));
        proxyTokenHub = calcCreateAddress(address(this), uint8(4));
        proxyLightClient = calcCreateAddress(address(this), uint8(5));
        proxyRelayerHub = calcCreateAddress(address(this), uint8(6));
        proxyBucketHub = calcCreateAddress(address(this), uint8(7));
        proxyObjectHub = calcCreateAddress(address(this), uint8(8));
        proxyGroupHub = calcCreateAddress(address(this), uint8(9));

        // 1. proxyAdmin
        address deployedProxyAdmin = address(new GnfdProxyAdmin());
        require(deployedProxyAdmin == proxyAdmin, "invalid proxyAdmin address");
    }

    function init(address[] memory addrs) internal {
        // use address list to avoid stack too deep
        require(addrs.length == 18, "invalid addrs length");

        require(_isContract(addrs[0]), "invalid implGovHub");
        require(_isContract(addrs[1]), "invalid implCrossChain");
        require(_isContract(addrs[2]), "invalid implTokenHub");
        require(_isContract(addrs[3]), "invalid implLightClient");
        require(_isContract(addrs[4]), "invalid implRelayerHub");
        require(_isContract(addrs[5]), "invalid implBucketHub");
        require(_isContract(addrs[6]), "invalid implObjectHub");
        require(_isContract(addrs[7]), "invalid implGroupHub");
        require(_isContract(addrs[8]), "invalid addBucketHub");
        require(_isContract(addrs[9]), "invalid addObjectHub");
        require(_isContract(addrs[10]), "invalid addGroupHub");
        require(_isContract(addrs[11]), "invalid bucketToken");
        require(_isContract(addrs[12]), "invalid objectToken");
        require(_isContract(addrs[13]), "invalid groupToken");
        require(_isContract(addrs[14]), "invalid memberToken");
        require(_isContract(addrs[15]), "invalid bucketRlp");
        require(_isContract(addrs[16]), "invalid objectRlp");
        require(_isContract(addrs[17]), "invalid groupRlp");

        implGovHub = addrs[0];
        implCrossChain = addrs[1];
        implTokenHub = addrs[2];
        implLightClient = addrs[3];
        implRelayerHub = addrs[4];
        implBucketHub = addrs[5];
        implObjectHub = addrs[6];
        implGroupHub = addrs[7];
        addBucketHub = addrs[8];
        addObjectHub = addrs[9];
        addGroupHub = addrs[10];
        bucketToken = addrs[11];
        objectToken = addrs[12];
        groupToken = addrs[13];
        memberToken = addrs[14];
        bucketRlp = addrs[15];
        objectRlp = addrs[16];
        groupRlp = addrs[17];
    }

    function deploy(address[] memory addrs, bytes calldata _initConsensusStateBytes) public {
        require(!deployed, "only not deployed");
        deployed = true;

        init(addrs);
        initConsensusStateBytes = _initConsensusStateBytes;

        // 2. GovHub, transfer ownership of proxyAdmin to GovHub
        address deployedProxyGovHub = address(new GnfdProxy(implGovHub, proxyAdmin, ""));
        require(deployedProxyGovHub == proxyGovHub, "invalid proxyGovHub address");

        // transfer ownership to proxyGovHub
        GnfdProxyAdmin(proxyAdmin).transferOwnership(proxyGovHub);
        require(GnfdProxyAdmin(proxyAdmin).owner() == proxyGovHub, "invalid proxyAdmin owner");

        // 3. CrossChain
        address deployedProxyCrossChain = address(new GnfdProxy(implCrossChain, proxyAdmin, ""));
        require(deployedProxyCrossChain == proxyCrossChain, "invalid proxyCrossChain address");

        // 4. TokenHub
        address deployedProxyTokenHub = address(new GnfdProxy(implTokenHub, proxyAdmin, ""));
        require(deployedProxyTokenHub == proxyTokenHub, "invalid proxyTokenHub address");

        // 5. GnfdLightClient
        address deployedProxyLightClient = address(new GnfdProxy(implLightClient, proxyAdmin, ""));
        require(deployedProxyLightClient == proxyLightClient, "invalid proxyLightClient address");

        // 6. RelayerHub
        address deployedProxyRelayerHub = address(new GnfdProxy(implRelayerHub, proxyAdmin, ""));
        require(deployedProxyRelayerHub == proxyRelayerHub, "invalid proxyRelayerHub address");

        // 7. BucketHub
        address deployedProxyBucketHub = address(new GnfdProxy(implBucketHub, proxyAdmin, ""));
        require(deployedProxyBucketHub == proxyBucketHub, "invalid proxyBucketHub address");

        // 8. ObjectHub
        address deployedProxyObjectHub = address(new GnfdProxy(implObjectHub, proxyAdmin, ""));
        require(deployedProxyObjectHub == proxyObjectHub, "invalid proxyObjectHub address");

        // 9. GroupHub
        address deployedProxyGroupHub = address(new GnfdProxy(implGroupHub, proxyAdmin, ""));
        require(deployedProxyGroupHub == proxyGroupHub, "invalid proxyGroupHub address");

        // 10. init contracts, set contracts addresses to GovHub
        CrossChain(payable(proxyCrossChain)).initialize(gnfdChainId);
        TokenHub(payable(proxyTokenHub)).initialize();
        GnfdLightClient(payable(proxyLightClient)).initialize(_initConsensusStateBytes);
        RelayerHub(payable(proxyRelayerHub)).initialize();
        BucketHub(payable(proxyBucketHub)).initialize(bucketToken, addBucketHub, bucketRlp);
        ObjectHub(payable(proxyObjectHub)).initialize(objectToken, addObjectHub, objectRlp);
        GroupHub(payable(proxyGroupHub)).initialize(groupToken, memberToken, addGroupHub, groupRlp);

        require(Config(deployedProxyCrossChain).PROXY_ADMIN() == proxyAdmin, "invalid proxyAdmin address on Config");
        require(Config(deployedProxyCrossChain).GOV_HUB() == proxyGovHub, "invalid proxyGovHub address on Config");
        require(
            Config(deployedProxyCrossChain).CROSS_CHAIN() == proxyCrossChain,
            "invalid proxyCrossChain address on Config"
        );
        require(
            Config(deployedProxyCrossChain).TOKEN_HUB() == proxyTokenHub,
            "invalid proxyTokenHub address on Config"
        );
        require(
            Config(deployedProxyCrossChain).LIGHT_CLIENT() == proxyLightClient,
            "invalid proxyLightClient address on Config"
        );
        require(
            Config(deployedProxyCrossChain).RELAYER_HUB() == proxyRelayerHub,
            "invalid proxyRelayerHub address on Config"
        );
    }

    function calcCreateAddress(address _deployer, uint8 _nonce) public pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _deployer, _nonce)))));
    }

    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}
