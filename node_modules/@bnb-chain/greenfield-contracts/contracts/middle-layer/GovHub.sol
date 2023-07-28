// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interface/IParamSubscriber.sol";
import "../interface/IProxyAdmin.sol";
import "../lib/BytesToTypes.sol";
import "../lib/Memory.sol";
import "../lib/CmnPkg.sol";

import "../lib/RLPDecode.sol";
import "../Config.sol";
import "../interface/IMiddleLayer.sol";

contract GovHub is Config, Initializable, IMiddleLayer {
    using RLPDecode for *;

    /*----------------- constants -----------------*/
    uint8 public constant PARAM_UPDATE_MESSAGE_TYPE = 0;

    uint32 public constant CODE_OK = 0;
    uint32 public constant ERROR_FAIL_DECODE = 100;
    uint32 public constant ERROR_TARGET_CONTRACT_FAIL = 101;

    bytes32 public constant UPGRADE_KEY_HASH = keccak256(abi.encodePacked("upgrade"));

    /*----------------- events -----------------*/
    event SuccessUpgrade(address target, address newImplementation);
    event FailUpgrade(address newImplementation, bytes message);
    event FailUpdateParam(bytes message);
    event ParamChange(string key, bytes value);

    struct ParamChangePackage {
        string key;
        bytes values;
        bytes targets;
    }

    /*----------------- external function -----------------*/
    function initialize() public initializer {}

    function handleSynPackage(
        uint8,
        bytes calldata msgBytes
    ) external onlyCrossChain returns (bytes memory responsePayload) {
        (ParamChangePackage memory proposal, bool success) = _decodeSynPackage(msgBytes);
        if (!success) {
            return CmnPkg.encodeCommonAckPackage(ERROR_FAIL_DECODE);
        }
        uint32 resCode = _notifyUpdates(proposal);
        if (resCode == CODE_OK) {
            return new bytes(0);
        } else {
            return CmnPkg.encodeCommonAckPackage(resCode);
        }
    }

    // should not happen
    function handleAckPackage(
        uint8,
        uint64,
        bytes calldata,
        uint256
    ) external view onlyCrossChain returns (uint256, address) {
        revert("receive unexpected ack package");
    }

    // should not happen
    function handleFailAckPackage(
        uint8,
        uint64,
        bytes calldata,
        uint256
    ) external view onlyCrossChain returns (uint256, address) {
        revert("receive unexpected fail ack package");
    }

    function _notifyUpdates(ParamChangePackage memory proposal) internal returns (uint32) {
        require(proposal.targets.length > 0 && proposal.targets.length % 20 == 0, "invalid target length");
        uint256 totalTargets = proposal.targets.length / 20;

        // upgrade contracts
        // TODO: The rollback mechanism will be added to the GovHub to prevent an upgrade error in extreme cases
        if (keccak256(abi.encodePacked(proposal.key)) == UPGRADE_KEY_HASH) {
            require(proposal.values.length == proposal.targets.length, "invalid values length");

            address target;
            address newImpl;
            uint256 lastVersion;
            uint256 newVersion;
            string memory lastName;
            string memory newName;
            for (uint256 i; i < totalTargets; ++i) {
                target = BytesToTypes.bytesToAddress(20 * (i + 1), proposal.targets);
                newImpl = BytesToTypes.bytesToAddress(20 * (i + 1), proposal.values);
                require(_isContract(target), "invalid target");
                require(_isContract(newImpl), "invalid implementation value");

                (lastVersion, lastName, ) = Config(target).versionInfo();
                IProxyAdmin(PROXY_ADMIN).upgrade(target, newImpl);
                (newVersion, newName, ) = Config(target).versionInfo();
                require(newVersion == lastVersion + 1, "invalid upgrade version");
                require(
                    keccak256(abi.encodePacked(lastName)) == keccak256(abi.encodePacked(newName)),
                    "invalid upgrade name"
                );

                emit SuccessUpgrade(target, newImpl);
            }
            return CODE_OK;
        }

        // update param
        require(totalTargets == 1, "Only single parameter update is allowed in a proposal");
        address _target = BytesToTypes.bytesToAddress(20, proposal.targets);
        try IParamSubscriber(_target).updateParam(proposal.key, proposal.values) {} catch (bytes memory reason) {
            emit FailUpdateParam(reason);
            return ERROR_TARGET_CONTRACT_FAIL;
        }
        return CODE_OK;
    }

    //rlp encode & decode function
    function _decodeSynPackage(bytes memory msgBytes) internal pure returns (ParamChangePackage memory, bool) {
        ParamChangePackage memory pkg;

        RLPDecode.Iterator memory iter = msgBytes.toRLPItem().iterator();
        bool success;
        uint256 idx;
        while (iter.hasNext()) {
            if (idx == 0) {
                pkg.key = string(iter.next().toBytes());
            } else if (idx == 1) {
                pkg.values = iter.next().toBytes();
            } else if (idx == 2) {
                pkg.targets = iter.next().toBytes();
                success = true;
            } else {
                break;
            }
            idx++;
        }
        return (pkg, success);
    }

    function versionInfo()
        external
        pure
        override
        returns (uint256 version, string memory name, string memory description)
    {
        return (100_001, "GovHub", "init version");
    }
}
