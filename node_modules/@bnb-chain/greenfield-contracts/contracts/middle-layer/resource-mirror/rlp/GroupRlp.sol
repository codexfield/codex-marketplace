// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./CmnRlp.sol";
import "../storage/GroupStorage.sol";

contract GroupRlp is GroupStorage, CmnRlp {
    using RLPEncode for *;
    using RLPDecode for *;

    /*----------------- encode -----------------*/
    function encodeCreateGroupSynPackage(CreateGroupSynPackage calldata synPkg) external pure returns (bytes memory) {
        bytes[] memory elements = new bytes[](3);
        elements[0] = synPkg.creator.encodeAddress();
        elements[1] = bytes(synPkg.name).encodeBytes();
        elements[2] = synPkg.extraData.encodeBytes();
        return wrapEncode(TYPE_CREATE, elements.encodeList());
    }

    function encodeUpdateGroupSynPackage(UpdateGroupSynPackage calldata synPkg) external pure returns (bytes memory) {
        bytes[] memory members = new bytes[](synPkg.members.length);
        for (uint256 i; i < synPkg.members.length; ++i) {
            members[i] = synPkg.members[i].encodeAddress();
        }

        bytes[] memory elements = new bytes[](5);
        elements[0] = synPkg.operator.encodeAddress();
        elements[1] = synPkg.id.encodeUint();
        elements[2] = uint256(synPkg.opType).encodeUint();
        elements[3] = members.encodeList();
        elements[4] = synPkg.extraData.encodeBytes();
        return wrapEncode(TYPE_UPDATE, elements.encodeList());
    }

    /*----------------- decode -----------------*/
    function decodeCreateGroupSynPackage(
        bytes calldata pkgBytes
    ) external pure returns (CreateGroupSynPackage memory synPkg, bool success) {
        RLPDecode.Iterator memory iter = pkgBytes.toRLPItem().iterator();

        uint256 idx;
        while (iter.hasNext()) {
            if (idx == 0) {
                synPkg.creator = iter.next().toAddress();
            } else if (idx == 1) {
                synPkg.name = string(iter.next().toBytes());
            } else if (idx == 2) {
                synPkg.extraData = iter.next().toBytes();
                success = true;
            } else {
                break;
            }
            idx++;
        }
        return (synPkg, success);
    }

    function decodeUpdateGroupSynPackage(
        bytes calldata pkgBytes
    ) external pure returns (UpdateGroupSynPackage memory synPkg, bool success) {
        RLPDecode.Iterator memory iter = pkgBytes.toRLPItem().iterator();

        uint256 idx;
        while (iter.hasNext()) {
            if (idx == 0) {
                synPkg.operator = iter.next().toAddress();
            } else if (idx == 1) {
                synPkg.id = iter.next().toUint();
            } else if (idx == 2) {
                synPkg.opType = UpdateGroupOpType(iter.next().toUint());
            } else if (idx == 3) {
                RLPDecode.RLPItem[] memory membersIter = iter.next().toList();
                address[] memory members = new address[](membersIter.length);
                for (uint256 i; i < membersIter.length; ++i) {
                    members[i] = membersIter[i].toAddress();
                }
                synPkg.members = members;
            } else if (idx == 4) {
                synPkg.extraData = iter.next().toBytes();
                success = true;
            } else {
                break;
            }
            idx++;
        }
        return (synPkg, success);
    }

    function decodeUpdateGroupAckPackage(
        bytes calldata pkgBytes
    ) external pure returns (UpdateGroupAckPackage memory, bool) {
        UpdateGroupAckPackage memory ackPkg;
        RLPDecode.Iterator memory iter = pkgBytes.toRLPItem().iterator();

        bool success;
        uint256 idx;
        while (iter.hasNext()) {
            if (idx == 0) {
                ackPkg.status = uint32(iter.next().toUint());
            } else if (idx == 1) {
                ackPkg.id = iter.next().toUint();
            } else if (idx == 2) {
                ackPkg.operator = iter.next().toAddress();
            } else if (idx == 3) {
                ackPkg.opType = UpdateGroupOpType(iter.next().toUint());
            } else if (idx == 4) {
                RLPDecode.RLPItem[] memory membersIter = iter.next().toList();
                address[] memory members = new address[](membersIter.length);
                for (uint256 i; i < membersIter.length; ++i) {
                    members[i] = membersIter[i].toAddress();
                }
                ackPkg.members = members;
            } else if (idx == 5) {
                ackPkg.extraData = iter.next().toBytes();
                success = true;
            } else {
                break;
            }
            idx++;
        }
        return (ackPkg, success);
    }
}
