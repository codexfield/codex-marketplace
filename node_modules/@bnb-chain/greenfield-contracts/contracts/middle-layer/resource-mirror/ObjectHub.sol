// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/structs/DoubleEndedQueueUpgradeable.sol";

import "./CmnHub.sol";
import "./utils/AccessControl.sol";
import "../../interface/IERC721NonTransferable.sol";
import "../../interface/IObjectHub.sol";

contract ObjectHub is ObjectStorage, AccessControl, CmnHub, IObjectHub {
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;
    using RLPEncode for *;
    using RLPDecode for *;

    function initialize(address _ERC721_token, address _additional, address _objectRlp) public initializer {
        ERC721Token = _ERC721_token;
        additional = _additional;
        rlp = _objectRlp;

        channelId = OBJECT_CHANNEL_ID;
    }

    /*----------------- middle-layer app function -----------------*/

    /**
     * @dev handle sync cross-chain package from BSC to GNFD
     *
     * @param msgBytes The rlp encoded message bytes sent from BSC to GNFD
     */
    function handleSynPackage(uint8, bytes calldata msgBytes) external override onlyCrossChain returns (bytes memory) {
        return _handleMirrorSynPackage(msgBytes);
    }

    // TODO: create object
    /**
     * @dev handle ack cross-chain package from GNFD，it means create/delete operation handled by GNFD successfully.
     *
     * @param sequence The sequence of the ack package
     * @param msgBytes The rlp encoded message bytes sent from GNFD
     * @param callbackGasLimit The gas limit for callback
     */
    function handleAckPackage(
        uint8,
        uint64 sequence,
        bytes calldata msgBytes,
        uint256 callbackGasLimit
    ) external override onlyCrossChain returns (uint256 remainingGas, address refundAddress) {
        RLPDecode.Iterator memory iter = msgBytes.toRLPItem().iterator();

        uint8 opType = uint8(iter.next().toUint());
        bytes memory pkgBytes;
        if (iter.hasNext()) {
            pkgBytes = iter.next().toBytes();
        } else {
            revert("wrong ack package");
        }

        if (opType == TYPE_DELETE) {
            (remainingGas, refundAddress) = _handleDeleteAckPackage(pkgBytes, sequence, callbackGasLimit);
        } else {
            revert("unexpected operation type");
        }
    }

    /**
     * @dev handle failed ack cross-chain package from GNFD, it means failed to cross-chain syn request to GNFD.
     *
     * @param sequence The sequence of the fail ack package
     * @param msgBytes The rlp encoded message bytes sent from GNFD
     * @param callbackGasLimit The gas limit for callback
     */
    function handleFailAckPackage(
        uint8 channelId,
        uint64 sequence,
        bytes calldata msgBytes,
        uint256 callbackGasLimit
    ) external override onlyCrossChain returns (uint256 remainingGas, address refundAddress) {
        RLPDecode.Iterator memory iter = msgBytes.toRLPItem().iterator();

        uint8 opType = uint8(iter.next().toUint());
        bytes memory pkgBytes;
        if (iter.hasNext()) {
            pkgBytes = iter.next().toBytes();
        } else {
            revert("wrong failAck package");
        }

        if (opType == TYPE_DELETE) {
            (remainingGas, refundAddress) = _handleDeleteFailAckPackage(pkgBytes, sequence, callbackGasLimit);
        } else {
            revert("unexpected operation type");
        }

        emit FailAckPkgReceived(channelId, msgBytes);
    }

    /*----------------- external function -----------------*/
    function versionInfo()
        external
        pure
        override
        returns (uint256 version, string memory name, string memory description)
    {
        return (500_001, "ObjectHub", "init version");
    }

    function grant(address, uint32, uint256) external override {
        delegateAdditional();
    }

    function revoke(address, uint32) external override {
        delegateAdditional();
    }

    function deleteObject(uint256) external payable returns (bool) {
        delegateAdditional();
    }

    function deleteObject(uint256, uint256, ExtraData memory) external payable returns (bool) {
        delegateAdditional();
    }
}
