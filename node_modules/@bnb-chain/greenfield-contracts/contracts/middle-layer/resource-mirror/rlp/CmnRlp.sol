// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../storage/CmnStorage.sol";
import "../../../lib/RLPDecode.sol";
import "../../../lib/RLPEncode.sol";

contract CmnRlp is CmnStorage {
    using RLPEncode for *;
    using RLPDecode for *;

    /*----------------- encode -----------------*/
    function encodeCmnMirrorAckPackage(CmnMirrorAckPackage calldata mirrorAckPkg) external pure returns (bytes memory) {
        bytes[] memory elements = new bytes[](2);
        elements[0] = uint256(mirrorAckPkg.status).encodeUint();
        elements[1] = mirrorAckPkg.id.encodeUint();
        return wrapEncode(TYPE_MIRROR, elements.encodeList());
    }

    function encodeCmnDeleteSynPackage(CmnDeleteSynPackage calldata synPkg) external pure returns (bytes memory) {
        bytes[] memory elements = new bytes[](3);
        elements[0] = synPkg.operator.encodeAddress();
        elements[1] = synPkg.id.encodeUint();
        elements[2] = synPkg.extraData.encodeBytes();
        return wrapEncode(TYPE_DELETE, elements.encodeList());
    }

    function encodeExtraData(ExtraData calldata _extraData) external pure returns (bytes memory) {
        bytes[] memory elements = new bytes[](4);
        elements[0] = _extraData.appAddress.encodeAddress();
        elements[1] = _extraData.refundAddress.encodeAddress();
        elements[2] = uint256(_extraData.failureHandleStrategy).encodeUint();
        elements[3] = _extraData.callbackData.encodeBytes();
        return elements.encodeList();
    }

    function wrapEncode(uint8 opType, bytes memory msgBytes) public pure returns (bytes memory) {
        bytes[] memory elements = new bytes[](2);
        elements[0] = opType.encodeUint();
        elements[1] = msgBytes.encodeBytes();
        return elements.encodeList();
    }

    /*----------------- decode -----------------*/
    function decodeCmnMirrorSynPackage(
        bytes calldata msgBytes
    ) external pure returns (CmnMirrorSynPackage memory, bool success) {
        CmnMirrorSynPackage memory synPkg;

        RLPDecode.Iterator memory msgIter = msgBytes.toRLPItem().iterator();
        uint8 opType = uint8(msgIter.next().toUint());
        require(opType == TYPE_MIRROR, "wrong syn operation type");

        RLPDecode.Iterator memory pkgIter;
        if (msgIter.hasNext()) {
            pkgIter = msgIter.next().toBytes().toRLPItem().iterator();
        } else {
            revert("wrong syn package");
        }

        uint256 idx;
        while (pkgIter.hasNext()) {
            if (idx == 0) {
                synPkg.id = pkgIter.next().toUint();
            } else if (idx == 1) {
                synPkg.owner = pkgIter.next().toAddress();
                success = true;
            } else {
                break;
            }
            idx++;
        }
        return (synPkg, success);
    }

    function decodeCmnCreateAckPackage(
        bytes calldata pkgBytes
    ) external pure returns (CmnCreateAckPackage memory, bool) {
        CmnCreateAckPackage memory ackPkg;
        RLPDecode.Iterator memory iter = pkgBytes.toRLPItem().iterator();

        bool success;
        uint256 idx;
        while (iter.hasNext()) {
            if (idx == 0) {
                ackPkg.status = uint32(iter.next().toUint());
            } else if (idx == 1) {
                ackPkg.id = iter.next().toUint();
            } else if (idx == 2) {
                ackPkg.creator = iter.next().toAddress();
            } else if (idx == 3) {
                ackPkg.extraData = iter.next().toBytes();
                success = true;
            } else {
                break;
            }
            idx++;
        }
        return (ackPkg, success);
    }

    function decodeCmnDeleteSynPackage(
        bytes calldata pkgBytes
    ) external pure returns (CmnDeleteSynPackage memory, bool success) {
        CmnDeleteSynPackage memory synPkg;
        RLPDecode.Iterator memory iter = pkgBytes.toRLPItem().iterator();

        uint256 idx;
        while (iter.hasNext()) {
            if (idx == 0) {
                synPkg.operator = iter.next().toAddress();
            } else if (idx == 1) {
                synPkg.id = iter.next().toUint();
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

    function decodeCmnDeleteAckPackage(
        bytes calldata pkgBytes
    ) external pure returns (CmnDeleteAckPackage memory, bool success) {
        CmnDeleteAckPackage memory ackPkg;
        RLPDecode.Iterator memory iter = pkgBytes.toRLPItem().iterator();

        uint256 idx;
        while (iter.hasNext()) {
            if (idx == 0) {
                ackPkg.status = uint32(iter.next().toUint());
            } else if (idx == 1) {
                ackPkg.id = iter.next().toUint();
            } else if (idx == 2) {
                ackPkg.extraData = iter.next().toBytes();
                success = true;
            } else {
                break;
            }
            idx++;
        }
        return (ackPkg, success);
    }

    function decodeExtraData(
        bytes calldata _extraDataBytes
    ) external pure returns (ExtraData memory _extraData, bool success) {
        RLPDecode.Iterator memory iter = _extraDataBytes.toRLPItem().iterator();

        uint256 idx;
        while (iter.hasNext()) {
            if (idx == 0) {
                _extraData.appAddress = iter.next().toAddress();
            } else if (idx == 1) {
                _extraData.refundAddress = iter.next().toAddress();
            } else if (idx == 2) {
                _extraData.failureHandleStrategy = FailureHandleStrategy(uint8(iter.next().toUint()));
            } else if (idx == 3) {
                _extraData.callbackData = iter.next().toBytes();
                success = true;
            } else {
                break;
            }
            idx++;
        }
    }
}
