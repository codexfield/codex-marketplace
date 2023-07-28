// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../middle-layer/resource-mirror/storage/GroupStorage.sol";

interface IGroupRlp {
    function decodeCmnCreateAckPackage(
        bytes memory pkgBytes
    ) external pure returns (CmnStorage.CmnCreateAckPackage memory, bool);

    function decodeCmnDeleteAckPackage(
        bytes memory pkgBytes
    ) external pure returns (CmnStorage.CmnDeleteAckPackage memory, bool success);

    function decodeCmnDeleteSynPackage(
        bytes memory pkgBytes
    ) external pure returns (CmnStorage.CmnDeleteSynPackage memory, bool success);

    function decodeCmnMirrorSynPackage(
        bytes memory msgBytes
    ) external pure returns (CmnStorage.CmnMirrorSynPackage memory, bool success);

    function decodeCreateGroupSynPackage(
        bytes memory pkgBytes
    ) external pure returns (GroupStorage.CreateGroupSynPackage memory synPkg, bool success);

    function decodeExtraData(
        bytes memory _extraDataBytes
    ) external pure returns (CmnStorage.ExtraData memory _extraData, bool success);

    function decodeUpdateGroupAckPackage(
        bytes memory pkgBytes
    ) external pure returns (GroupStorage.UpdateGroupAckPackage memory, bool);

    function decodeUpdateGroupSynPackage(
        bytes memory pkgBytes
    ) external pure returns (GroupStorage.UpdateGroupSynPackage memory synPkg, bool success);

    function encodeCmnDeleteSynPackage(
        CmnStorage.CmnDeleteSynPackage memory synPkg
    ) external pure returns (bytes memory);

    function encodeCmnMirrorAckPackage(
        CmnStorage.CmnMirrorAckPackage memory mirrorAckPkg
    ) external pure returns (bytes memory);

    function encodeCreateGroupSynPackage(
        GroupStorage.CreateGroupSynPackage memory synPkg
    ) external pure returns (bytes memory);

    function encodeExtraData(CmnStorage.ExtraData memory _extraData) external pure returns (bytes memory);

    function encodeUpdateGroupSynPackage(
        GroupStorage.UpdateGroupSynPackage memory synPkg
    ) external pure returns (bytes memory);

    function wrapEncode(uint8 opType, bytes memory msgBytes) external pure returns (bytes memory);
}
