// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./CmnRlp.sol";
import "../storage/BucketStorage.sol";

contract BucketRlp is BucketStorage, CmnRlp {
    using RLPEncode for *;
    using RLPDecode for *;

    /*----------------- encode -----------------*/
    function encodeCreateBucketSynPackage(CreateBucketSynPackage calldata synPkg) external pure returns (bytes memory) {
        bytes[] memory elements = new bytes[](9);
        elements[0] = synPkg.creator.encodeAddress();
        elements[1] = bytes(synPkg.name).encodeBytes();
        elements[2] = uint256(synPkg.visibility).encodeUint();
        elements[3] = synPkg.paymentAddress.encodeAddress();
        elements[4] = synPkg.primarySpAddress.encodeAddress();
        elements[5] = synPkg.primarySpApprovalExpiredHeight.encodeUint();
        elements[6] = synPkg.primarySpSignature.encodeBytes();
        elements[7] = uint256(synPkg.chargedReadQuota).encodeUint();
        elements[8] = synPkg.extraData.encodeBytes();
        return wrapEncode(TYPE_CREATE, elements.encodeList());
    }

    /*----------------- decode -----------------*/
    function decodeCreateBucketSynPackage(
        bytes calldata pkgBytes
    ) external pure returns (CreateBucketSynPackage memory synPkg, bool success) {
        RLPDecode.Iterator memory iter = pkgBytes.toRLPItem().iterator();

        uint256 idx;
        while (iter.hasNext()) {
            if (idx == 0) {
                synPkg.creator = iter.next().toAddress();
            } else if (idx == 1) {
                synPkg.name = string(iter.next().toBytes());
            } else if (idx == 2) {
                synPkg.visibility = BucketVisibilityType(iter.next().toUint());
            } else if (idx == 3) {
                synPkg.paymentAddress = iter.next().toAddress();
            } else if (idx == 4) {
                synPkg.primarySpAddress = iter.next().toAddress();
            } else if (idx == 5) {
                synPkg.primarySpApprovalExpiredHeight = iter.next().toUint();
            } else if (idx == 6) {
                synPkg.primarySpSignature = iter.next().toBytes();
            } else if (idx == 7) {
                synPkg.chargedReadQuota = uint64(iter.next().toUint());
            } else if (idx == 8) {
                synPkg.extraData = iter.next().toBytes();
                success = true;
            } else {
                break;
            }
            idx++;
        }
        return (synPkg, success);
    }
}
