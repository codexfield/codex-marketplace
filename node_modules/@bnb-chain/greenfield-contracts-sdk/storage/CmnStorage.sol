// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

/**
 * @dev Necessary common data structures.
 */
contract CmnStorage {
    // role
    bytes32 public constant ROLE_CREATE = keccak256("ROLE_CREATE");
    bytes32 public constant ROLE_DELETE = keccak256("ROLE_DELETE");

    /**
     * @dev The data structure for callback.
     */
    struct ExtraData {
        address appAddress;
        address refundAddress;
        FailureHandleStrategy failureHandleStrategy;
        bytes callbackData;
    }

    enum FailureHandleStrategy {
        BlockOnFail, // If a package fails, the dApp cannot send new cross-chain txs until the failed packages are handled in the order they were received.
        CacheOnFail, // When a package fails, it is cached for later handling. New cross-chain txs are still allowed to be sent.
        SkipOnFail // Failed packages are ignored and will not affect subsequent ross-chain txs.
    }
}
