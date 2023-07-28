// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/structs/DoubleEndedQueueUpgradeable.sol";

import "./CmnHub.sol";
import "./utils/AccessControl.sol";
import "../../interface/IERC1155NonTransferable.sol";
import "../../interface/IERC721NonTransferable.sol";
import "../../interface/IGroupHub.sol";
import "../../interface/IGroupRlp.sol";

contract GroupHub is GroupStorage, AccessControl, CmnHub, IGroupHub {
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;
    using RLPEncode for *;
    using RLPDecode for *;

    function initialize(
        address _ERC721_token,
        address _ERC1155_token,
        address _additional,
        address _groupRlp
    ) public initializer {
        ERC721Token = _ERC721_token;
        ERC1155Token = _ERC1155_token;
        additional = _additional;
        rlp = _groupRlp;

        channelId = GROUP_CHANNEL_ID;
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

    /**
     * @dev handle ack cross-chain package from GNFD，it means create/delete/update operation handled by GNFD successfully.
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

        if (opType == TYPE_CREATE) {
            (remainingGas, refundAddress) = _handleCreateAckPackage(pkgBytes, sequence, callbackGasLimit);
        } else if (opType == TYPE_DELETE) {
            (remainingGas, refundAddress) = _handleDeleteAckPackage(pkgBytes, sequence, callbackGasLimit);
        } else if (opType == TYPE_UPDATE) {
            (remainingGas, refundAddress) = _handleUpdateGroupAckPackage(pkgBytes, sequence, callbackGasLimit);
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

        if (opType == TYPE_CREATE) {
            (remainingGas, refundAddress) = _handleCreateFailAckPackage(pkgBytes, sequence, callbackGasLimit);
        } else if (opType == TYPE_DELETE) {
            (remainingGas, refundAddress) = _handleDeleteFailAckPackage(pkgBytes, sequence, callbackGasLimit);
        } else if (opType == TYPE_UPDATE) {
            (remainingGas, refundAddress) = _handleUpdateFailAckPackage(pkgBytes, sequence, callbackGasLimit);
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
        return (600_001, "GroupHub", "init version");
    }

    function grant(address, uint32, uint256) external override {
        delegateAdditional();
    }

    function revoke(address, uint32) external override {
        delegateAdditional();
    }

    function createGroup(address, string memory) external payable returns (bool) {
        delegateAdditional();
    }

    function createGroup(address, string memory, uint256, ExtraData memory) external payable returns (bool) {
        delegateAdditional();
    }

    function deleteGroup(uint256) external payable returns (bool) {
        delegateAdditional();
    }

    function deleteGroup(uint256, uint256, ExtraData memory) external payable returns (bool) {
        delegateAdditional();
    }

    function updateGroup(UpdateGroupSynPackage memory) external payable returns (bool) {
        delegateAdditional();
    }

    function updateGroup(UpdateGroupSynPackage memory, uint256, ExtraData memory) external payable returns (bool) {
        delegateAdditional();
    }

    /*----------------- update param -----------------*/
    function updateParam(string calldata key, bytes calldata value) external override onlyGov {
        if (Memory.compareStrings(key, "ERC721BaseURI")) {
            IERC721NonTransferable(ERC721Token).setBaseURI(string(value));
        } else if (Memory.compareStrings(key, "ERC1155BaseURI")) {
            IERC1155NonTransferable(ERC1155Token).setBaseURI(string(value));
        } else {
            revert("unknown param");
        }
        emit ParamChange(key, value);
    }

    /*----------------- internal function -----------------*/
    function _handleUpdateGroupAckPackage(
        bytes memory pkgBytes,
        uint64 sequence,
        uint256 callbackGasLimit
    ) internal returns (uint256 remainingGas, address refundAddress) {
        (UpdateGroupAckPackage memory ackPkg, bool success) = IGroupRlp(rlp).decodeUpdateGroupAckPackage(pkgBytes);
        require(success, "unrecognized update ack package");

        if (ackPkg.status == STATUS_SUCCESS) {
            _doUpdate(ackPkg);
        } else if (ackPkg.status == STATUS_FAILED) {
            emit UpdateFailed(ackPkg.operator, ackPkg.id, uint8(ackPkg.opType));
        } else {
            revert("unexpected status code");
        }

        if (ackPkg.extraData.length > 0) {
            ExtraData memory extraData;
            (extraData, success) = IGroupRlp(rlp).decodeExtraData(ackPkg.extraData);
            require(success, "unrecognized extra data");

            if (extraData.appAddress != address(0) && callbackGasLimit >= 2300) {
                bytes memory reason;
                bool failed;
                uint256 gasBefore = gasleft();
                try
                    IApplication(extraData.appAddress).greenfieldCall{ gas: callbackGasLimit }(
                        ackPkg.status,
                        channelId,
                        TYPE_UPDATE,
                        ackPkg.id,
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
                            ackPkg.status,
                            TYPE_UPDATE,
                            ackPkg.id,
                            extraData.callbackData,
                            reason
                        );
                        retryQueue[extraData.appAddress].pushBack(pkgHash);
                    }
                }
            }
        }
    }

    function _doUpdate(UpdateGroupAckPackage memory ackPkg) internal {
        if (ackPkg.opType == UpdateGroupOpType.AddMembers) {
            for (uint256 i; i < ackPkg.members.length; ++i) {
                IERC1155NonTransferable(ERC1155Token).mint(ackPkg.members[i], ackPkg.id, 1, "");
            }
        } else if (ackPkg.opType == UpdateGroupOpType.RemoveMembers) {
            for (uint256 i; i < ackPkg.members.length; ++i) {
                // skip if the member has no token
                if (IERC1155NonTransferable(ERC1155Token).balanceOf(ackPkg.members[i], ackPkg.id) == 0) {
                    continue;
                }
                IERC1155NonTransferable(ERC1155Token).burn(ackPkg.members[i], ackPkg.id, 1);
            }
        } else {
            revert("unexpected update operation");
        }
        emit UpdateSuccess(ackPkg.operator, ackPkg.id, uint8(ackPkg.opType));
    }

    function _handleCreateFailAckPackage(
        bytes memory pkgBytes,
        uint64 sequence,
        uint256 callbackGasLimit
    ) internal returns (uint256 remainingGas, address refundAddress) {
        (CreateGroupSynPackage memory synPkg, bool success) = IGroupRlp(rlp).decodeCreateGroupSynPackage(pkgBytes);
        require(success, "unrecognized create group fail ack package");

        if (synPkg.extraData.length > 0) {
            ExtraData memory extraData;
            (extraData, success) = IGroupRlp(rlp).decodeExtraData(synPkg.extraData);
            require(success, "unrecognized extra data");

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

    function _handleUpdateFailAckPackage(
        bytes memory pkgBytes,
        uint64 sequence,
        uint256 callbackGasLimit
    ) internal returns (uint256 remainingGas, address refundAddress) {
        (UpdateGroupSynPackage memory synPkg, bool success) = IGroupRlp(rlp).decodeUpdateGroupSynPackage(pkgBytes);
        require(success, "unrecognized create group fail ack package");

        if (synPkg.extraData.length > 0) {
            ExtraData memory extraData;
            (extraData, success) = IGroupRlp(rlp).decodeExtraData(synPkg.extraData);
            require(success, "unrecognized extra data");

            if (extraData.appAddress != address(0) && callbackGasLimit >= 2300) {
                bytes memory reason;
                bool failed;
                uint256 gasBefore = gasleft();
                try
                    IApplication(extraData.appAddress).greenfieldCall{ gas: callbackGasLimit }(
                        STATUS_UNEXPECTED,
                        channelId,
                        TYPE_UPDATE,
                        synPkg.id,
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
                            TYPE_UPDATE,
                            synPkg.id,
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
