// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

library CmnPkg {
    struct CommonAckPackage {
        uint32 code;
    }

    function encodeCommonAckPackage(uint32 code) internal pure returns (bytes memory) {
        return abi.encode(code);
    }

    function decodeCommonAckPackage(bytes memory msgBytes) internal pure returns (CommonAckPackage memory ackPkg, bool) {
        ackPkg = abi.decode(msgBytes, (CommonAckPackage));
        return (ackPkg, true);
    }
}
