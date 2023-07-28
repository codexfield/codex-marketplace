// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/structs/DoubleEndedQueueUpgradeable.sol";

contract PackageQueue {
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;

    // app address => retry queue of package hash
    mapping(address => DoubleEndedQueueUpgradeable.Bytes32Deque) public retryQueue;
    // app retry package hash => retry package
    mapping(bytes32 => RetryPackage) public packageMap;

    // PlaceHolder reserve for future usage
    uint256[50] public PkgQueueSlots;

    /*
     * This enum provides different strategies for handling a failed ACK package.
     */
    enum FailureHandleStrategy {
        BlockOnFail, // If a package fails, the subsequent SYN packages will be blocked until the failed ACK packages are handled in the order they were received.
        CacheOnFail, // When a package fails, it is cached for later handling. New SYN packages will continue to be handled normally.
        SkipOnFail // Failed ACK packages are ignored and will not affect subsequent SYN packages.
    }

    struct RetryPackage {
        address appAddress;
        uint32 status;
        uint8 operationType;
        uint256 resourceId;
        bytes callbackData;
        bytes failReason;
    }

    event AppHandleAckPkgFailed(address indexed appAddress, bytes32 pkgHash, bytes failReason);
    event AppHandleFailAckPkgFailed(address indexed appAddress, bytes32 pkgHash, bytes failReason);
}
