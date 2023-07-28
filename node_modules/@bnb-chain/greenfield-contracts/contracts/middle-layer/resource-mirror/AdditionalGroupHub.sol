// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/DoubleEndedQueueUpgradeable.sol";

import "./storage/GroupStorage.sol";
import "./utils/AccessControl.sol";
import "../../interface/IApplication.sol";
import "../../interface/ICrossChain.sol";
import "../../interface/IERC721NonTransferable.sol";
import "../../interface/IGroupRlp.sol";

// Highlight: This contract must have the same storage layout as GroupHub
// which means same state variables and same order of state variables.
// Because it will be used as a delegate call target.
// NOTE: The inherited contracts order must be the same as GroupHub.
contract AdditionalGroupHub is GroupStorage, AccessControl {
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;

    /*----------------- external function -----------------*/
    /**
     * @dev grant some authorization to an account
     *
     * @param account The address of the account to be granted
     * @param acCode The authorization code
     * @param expireTime The expiration time of the authorization
     */
    function grant(address account, uint32 acCode, uint256 expireTime) external {
        if (expireTime == 0) {
            expireTime = block.timestamp + 30 days; // 30 days in default
        }

        if (acCode & AUTH_CODE_CREATE != 0) {
            acCode = acCode & ~AUTH_CODE_CREATE;
            grantRole(ROLE_CREATE, account, expireTime);
        }
        if (acCode & AUTH_CODE_DELETE != 0) {
            acCode = acCode & ~AUTH_CODE_DELETE;
            grantRole(ROLE_DELETE, account, expireTime);
        }
        if (acCode & AUTH_CODE_UPDATE != 0) {
            acCode = acCode & ~AUTH_CODE_UPDATE;
            grantRole(ROLE_UPDATE, account, expireTime);
        }

        require(acCode == 0, "invalid authorization code");
    }

    /**
     * @dev revoke some authorization from an account
     *
     * @param account The address of the account to be revoked
     * @param acCode The authorization code
     */
    function revoke(address account, uint32 acCode) external {
        if (acCode & AUTH_CODE_CREATE != 0) {
            acCode = acCode & ~AUTH_CODE_CREATE;
            revokeRole(ROLE_CREATE, account);
        }
        if (acCode & AUTH_CODE_DELETE != 0) {
            acCode = acCode & ~AUTH_CODE_DELETE;
            revokeRole(ROLE_DELETE, account);
        }
        if (acCode & AUTH_CODE_UPDATE != 0) {
            acCode = acCode & ~AUTH_CODE_UPDATE;
            revokeRole(ROLE_UPDATE, account);
        }

        require(acCode == 0, "invalid authorization code");
    }

    /**
     * @dev create a group and send cross-chain request from BSC to GNFD
     *
     * @param owner The group's owner
     * @param name The group's name
     */
    function createGroup(address owner, string memory name) external payable returns (bool) {
        // check relay fee
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(CROSS_CHAIN).getRelayFees();
        require(msg.value >= relayFee + minAckRelayFee, "not enough fee");
        uint256 _ackRelayFee = msg.value - relayFee;

        // check authorization
        if (msg.sender != owner) {
            require(hasRole(ROLE_CREATE, owner, msg.sender), "no permission to create");
        }

        // make sure the extra data is as expected
        CreateGroupSynPackage memory synPkg = CreateGroupSynPackage({ creator: owner, name: name, extraData: "" });

        ICrossChain(CROSS_CHAIN).sendSynPackage(
            GROUP_CHANNEL_ID,
            IGroupRlp(rlp).encodeCreateGroupSynPackage(synPkg),
            relayFee,
            _ackRelayFee
        );
        emit CreateSubmitted(owner, msg.sender, name);
        return true;
    }

    /**
     * @dev create a group and send cross-chain request from BSC to GNFD.
     * Callback function will be called when the request is processed.
     *
     * @param owner The group's owner
     * @param name The group's name
     * @param callbackGasLimit The gas limit for callback function
     * @param extraData Extra data for callback function. The `appAddress` in `extraData` will be ignored.
     * It will be reset as the `msg.sender` all the time.
     */
    function createGroup(
        address owner,
        string memory name,
        uint256 callbackGasLimit,
        ExtraData memory extraData
    ) external payable returns (bool) {
        // check relay fee and callback fee
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(CROSS_CHAIN).getRelayFees();
        uint256 callbackGasPrice = ICrossChain(CROSS_CHAIN).callbackGasPrice();
        require(msg.value >= relayFee + minAckRelayFee + callbackGasLimit * callbackGasPrice, "not enough fee");
        uint256 _ackRelayFee = msg.value - relayFee;

        // check package queue
        if (extraData.failureHandleStrategy == FailureHandleStrategy.BlockOnFail) {
            require(retryQueue[msg.sender].empty(), "retry queue is not empty");
        }

        // check authorization
        if (msg.sender != owner) {
            require(hasRole(ROLE_CREATE, owner, msg.sender), "no permission to create");
        }

        // make sure the extra data is as expected
        extraData.appAddress = msg.sender;
        CreateGroupSynPackage memory synPkg = CreateGroupSynPackage({
            creator: owner,
            name: name,
            extraData: IGroupRlp(rlp).encodeExtraData(extraData)
        });

        // check refund address
        (bool success, ) = extraData.refundAddress.call("");
        require(success && (extraData.refundAddress != address(0)), "invalid refund address");

        ICrossChain(CROSS_CHAIN).sendSynPackage(
            GROUP_CHANNEL_ID,
            IGroupRlp(rlp).encodeCreateGroupSynPackage(synPkg),
            relayFee,
            _ackRelayFee
        );
        emit CreateSubmitted(owner, msg.sender, name);
        return true;
    }

    /**
     * @dev delete a group and send cross-chain request from BSC to GNFD
     *
     * @param id The group's id
     */
    function deleteGroup(uint256 id) external payable returns (bool) {
        // check relay fee
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(CROSS_CHAIN).getRelayFees();
        require(msg.value >= relayFee + minAckRelayFee, "not enough fee");
        uint256 _ackRelayFee = msg.value - relayFee;

        // check authorization
        address owner = IERC721NonTransferable(ERC721Token).ownerOf(id);
        if (
            !(msg.sender == owner ||
                IERC721NonTransferable(ERC721Token).getApproved(id) == msg.sender ||
                IERC721NonTransferable(ERC721Token).isApprovedForAll(owner, msg.sender))
        ) {
            require(hasRole(ROLE_DELETE, owner, msg.sender), "no delete permission");
        }

        // make sure the extra data is as expected
        CmnDeleteSynPackage memory synPkg = CmnDeleteSynPackage({ operator: owner, id: id, extraData: "" });

        ICrossChain(CROSS_CHAIN).sendSynPackage(
            GROUP_CHANNEL_ID,
            IGroupRlp(rlp).encodeCmnDeleteSynPackage(synPkg),
            relayFee,
            _ackRelayFee
        );
        emit DeleteSubmitted(owner, msg.sender, id);
        return true;
    }

    /**
     * @dev delete a group and send cross-chain request from BSC to GNFD
     * Callback function will be called when the request is processed.
     *
     * @param id The group's id
     * @param callbackGasLimit The gas limit for callback function
     * @param extraData Extra data for callback function. The `appAddress` in `extraData` will be ignored.
     * It will be reset as the `msg.sender` all the time.
     */
    function deleteGroup(
        uint256 id,
        uint256 callbackGasLimit,
        ExtraData memory extraData
    ) external payable returns (bool) {
        // check relay fee and callback fee
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(CROSS_CHAIN).getRelayFees();
        uint256 callbackGasPrice = ICrossChain(CROSS_CHAIN).callbackGasPrice();
        require(msg.value >= relayFee + minAckRelayFee + callbackGasLimit * callbackGasPrice, "not enough fee");
        uint256 _ackRelayFee = msg.value - relayFee;

        // check package queue
        if (extraData.failureHandleStrategy == FailureHandleStrategy.BlockOnFail) {
            require(retryQueue[msg.sender].empty(), "retry queue is not empty");
        }

        // check authorization
        address owner = IERC721NonTransferable(ERC721Token).ownerOf(id);
        if (
            !(msg.sender == owner ||
                IERC721NonTransferable(ERC721Token).getApproved(id) == msg.sender ||
                IERC721NonTransferable(ERC721Token).isApprovedForAll(owner, msg.sender))
        ) {
            require(hasRole(ROLE_DELETE, owner, msg.sender), "no delete permission");
        }

        // make sure the extra data is as expected
        extraData.appAddress = msg.sender;
        CmnDeleteSynPackage memory synPkg = CmnDeleteSynPackage({
            operator: owner,
            id: id,
            extraData: IGroupRlp(rlp).encodeExtraData(extraData)
        });

        // check refund address
        (bool success, ) = extraData.refundAddress.call("");
        require(success && (extraData.refundAddress != address(0)), "invalid refund address"); // the refund address must be payable

        ICrossChain(CROSS_CHAIN).sendSynPackage(
            GROUP_CHANNEL_ID,
            IGroupRlp(rlp).encodeCmnDeleteSynPackage(synPkg),
            relayFee,
            _ackRelayFee
        );
        emit DeleteSubmitted(owner, msg.sender, id);
        return true;
    }

    /**
     * @dev update a group's member and send cross-chain request from BSC to GNFD
     *
     * @param synPkg Package containing information of the group to be updated
     */
    function updateGroup(UpdateGroupSynPackage memory synPkg) external payable returns (bool) {
        // check relay fee
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(CROSS_CHAIN).getRelayFees();
        require(msg.value >= relayFee + minAckRelayFee, "not enough fee");
        uint256 _ackRelayFee = msg.value - relayFee;

        // check authorization
        address owner = IERC721NonTransferable(ERC721Token).ownerOf(synPkg.id);
        if (
            !(msg.sender == owner ||
                IERC721NonTransferable(ERC721Token).getApproved(synPkg.id) == msg.sender ||
                IERC721NonTransferable(ERC721Token).isApprovedForAll(owner, msg.sender))
        ) {
            require(hasRole(ROLE_UPDATE, owner, msg.sender), "no update permission");
        }

        // make sure the extra data is as expected
        synPkg.extraData = "";

        ICrossChain(CROSS_CHAIN).sendSynPackage(
            GROUP_CHANNEL_ID,
            IGroupRlp(rlp).encodeUpdateGroupSynPackage(synPkg),
            relayFee,
            _ackRelayFee
        );
        emit UpdateSubmitted(owner, msg.sender, synPkg.id, uint8(synPkg.opType), synPkg.members);
        return true;
    }

    /**
     * @dev update a group's member and send cross-chain request from BSC to GNFD
     * Callback function will be called when the request is processed.
     *
     * @param synPkg Package containing information of the group to be updated
     * @param callbackGasLimit The gas limit for callback function
     * @param extraData Extra data for callback function. The `appAddress` in `extraData` will be ignored.
     * It will be reset as the `msg.sender` all the time.
     */
    function updateGroup(
        UpdateGroupSynPackage memory synPkg,
        uint256 callbackGasLimit,
        ExtraData memory extraData
    ) external payable returns (bool) {
        // check relay fee and callback fee
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(CROSS_CHAIN).getRelayFees();
        uint256 callbackGasPrice = ICrossChain(CROSS_CHAIN).callbackGasPrice();
        require(msg.value >= relayFee + minAckRelayFee + callbackGasLimit * callbackGasPrice, "not enough fee");
        uint256 _ackRelayFee = msg.value - relayFee;

        // check package queue
        if (extraData.failureHandleStrategy == FailureHandleStrategy.BlockOnFail) {
            require(retryQueue[msg.sender].empty(), "retry queue is not empty");
        }

        // check authorization
        address owner = IERC721NonTransferable(ERC721Token).ownerOf(synPkg.id);
        if (
            !(msg.sender == owner ||
                IERC721NonTransferable(ERC721Token).getApproved(synPkg.id) == msg.sender ||
                IERC721NonTransferable(ERC721Token).isApprovedForAll(owner, msg.sender))
        ) {
            require(hasRole(ROLE_UPDATE, owner, msg.sender), "no update permission");
        }

        // make sure the extra data is as expected
        extraData.appAddress = msg.sender;
        synPkg.extraData = IGroupRlp(rlp).encodeExtraData(extraData);

        // check refund address
        (bool success, ) = extraData.refundAddress.call("");
        require(success && (extraData.refundAddress != address(0)), "invalid refund address"); // the refund address must be payable

        ICrossChain(CROSS_CHAIN).sendSynPackage(
            GROUP_CHANNEL_ID,
            IGroupRlp(rlp).encodeUpdateGroupSynPackage(synPkg),
            relayFee,
            _ackRelayFee
        );
        emit UpdateSubmitted(owner, msg.sender, synPkg.id, uint8(synPkg.opType), synPkg.members);
        return true;
    }
}
