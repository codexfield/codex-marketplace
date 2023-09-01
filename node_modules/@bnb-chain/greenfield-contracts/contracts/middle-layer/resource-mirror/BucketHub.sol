// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/structs/DoubleEndedQueueUpgradeable.sol";

import "./CmnHub.sol";
import "./utils/GnfdAccessControl.sol";
import "../../interface/IBucketHub.sol";
import "../../interface/IERC721NonTransferable.sol";

contract BucketHub is BucketStorage, GnfdAccessControl, CmnHub, IBucketHub {
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;

    function initialize(address _ERC721_token, address _additional) public initializer {
        ERC721Token = _ERC721_token;
        additional = _additional;

        channelId = BUCKET_CHANNEL_ID;
    }

    /*----------------- middle-layer app function -----------------*/
    /**
     * @dev handle sync cross-chain package from BSC to GNFD
     *
     * @param msgBytes The encoded message bytes sent from BSC to GNFD
     */
    function handleSynPackage(uint8, bytes calldata msgBytes) external override onlyCrossChain returns (bytes memory) {
        return _handleMirrorSynPackage(msgBytes);
    }

    /**
     * @dev handle ack cross-chain package from GNFD，it means create/delete operation handled by GNFD successfully.
     *
     * @param sequence The sequence of the ack package
     * @param msgBytes The encoded message bytes sent from GNFD
     * @param callbackGasLimit The gas limit for callback
     */
    function handleAckPackage(
        uint8,
        uint64 sequence,
        bytes calldata msgBytes,
        uint256 callbackGasLimit
    ) external override onlyCrossChain returns (uint256 remainingGas, address refundAddress) {
        uint8 opType = uint8(msgBytes[0]);
        bytes memory pkgBytes = msgBytes[1:];

        if (opType == TYPE_CREATE) {
            (remainingGas, refundAddress) = _handleCreateAckPackage(pkgBytes, sequence, callbackGasLimit);
        } else if (opType == TYPE_DELETE) {
            (remainingGas, refundAddress) = _handleDeleteAckPackage(pkgBytes, sequence, callbackGasLimit);
        } else {
            revert("unexpected operation type");
        }
    }

    /**
     * @dev handle failed ack cross-chain package from GNFD, it means failed to cross-chain syn request to GNFD.
     *
     * @param sequence The sequence of the fail ack package
     * @param msgBytes The encoded message bytes sent from GNFD
     * @param callbackGasLimit The gas limit for callback
     */
    function handleFailAckPackage(
        uint8 channelId,
        uint64 sequence,
        bytes calldata msgBytes,
        uint256 callbackGasLimit
    ) external override onlyCrossChain returns (uint256 remainingGas, address refundAddress) {
        uint8 opType = uint8(msgBytes[0]);
        bytes memory pkgBytes = msgBytes[1:];

        if (opType == TYPE_CREATE) {
            (remainingGas, refundAddress) = _handleCreateFailAckPackage(pkgBytes, sequence, callbackGasLimit);
        } else if (opType == TYPE_DELETE) {
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
        return (400_001, "BucketHub", "init version");
    }

    function grant(address, uint32, uint256) external override {
        delegateAdditional();
    }

    function revoke(address, uint32) external override {
        delegateAdditional();
    }

    function createBucket(CreateBucketSynPackage memory) external payable returns (bool) {
        delegateAdditional();
    }

    function createBucket(CreateBucketSynPackage memory, uint256, ExtraData memory) external payable returns (bool) {
        delegateAdditional();
    }

    function deleteBucket(uint256) external payable returns (bool) {
        delegateAdditional();
    }

    function deleteBucket(uint256, uint256, ExtraData memory) external payable returns (bool) {
        delegateAdditional();
    }

    /*----------------- internal function -----------------*/
    function _handleCreateFailAckPackage(
        bytes memory pkgBytes,
        uint64 sequence,
        uint256 callbackGasLimit
    ) internal returns (uint256 remainingGas, address refundAddress) {
        CreateBucketSynPackage memory synPkg = abi.decode(pkgBytes, (CreateBucketSynPackage));

        if (synPkg.extraData.length > 0) {
            ExtraData memory extraData = abi.decode(synPkg.extraData, (ExtraData));

            if (extraData.appAddress != address(0) && callbackGasLimit >= 2300) {
                bytes memory reason;
                bool failed;
                uint256 gasBefore = gasleft();
                try
                    IApplication(extraData.appAddress).greenfieldCall{ gas: callbackGasLimit }(
                        STATUS_UNEXPECTED,
                        channelId,
                        TYPE_CREATE,
                        0,
                        extraData.callbackData
                    )
                {} catch Error(string memory error) {
                    reason = bytes(error);
                    failed = true;
                } catch (bytes memory lowLevelData) {
                    reason = lowLevelData;
                    failed = true;
                }

                uint256 gasUsed = gasBefore - gasleft();
                remainingGas = callbackGasLimit > gasUsed ? callbackGasLimit - gasUsed : 0;
                refundAddress = extraData.refundAddress;

                if (failed) {
                    bytes32 pkgHash = keccak256(abi.encodePacked(channelId, sequence));
                    emit AppHandleAckPkgFailed(extraData.appAddress, pkgHash, reason);
                    if (extraData.failureHandleStrategy != FailureHandleStrategy.SkipOnFail) {
                        packageMap[pkgHash] = RetryPackage(
                            extraData.appAddress,
                            STATUS_UNEXPECTED,
                            TYPE_CREATE,
                            0,
                            extraData.callbackData,
                            reason
                        );
                        retryQueue[extraData.appAddress].pushBack(pkgHash);
                    }
                }
            }
        }
    }
}
