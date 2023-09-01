// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/DoubleEndedQueueUpgradeable.sol";

import "./storage/BucketStorage.sol";
import "./utils/GnfdAccessControl.sol";
import "../../interface/IApplication.sol";
import "../../interface/ICrossChain.sol";
import "../../interface/IERC721NonTransferable.sol";

// Highlight: This contract must have the same storage layout as BucketHub
// which means same state variables and same order of state variables.
// Because it will be used as a delegate call target.
// NOTE: The inherited contracts order must be the same as BucketHub.
contract AdditionalBucketHub is BucketStorage, GnfdAccessControl {
    // PlaceHolder corresponding to `Initializable` contract
    uint8 private _initialized;
    bool private _initializing;

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

        require(acCode == 0, "invalid authorization code");
    }

    /**
     * @dev create a bucket and send cross-chain request from BSC to GNFD
     *
     * @param synPkg Package containing information of the bucket to be created
     */
    function createBucket(CreateBucketSynPackage memory synPkg) external payable returns (bool) {
        // check relay fee
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(CROSS_CHAIN).getRelayFees();
        require(msg.value >= relayFee + minAckRelayFee, "not enough fee");
        uint256 _ackRelayFee = msg.value - relayFee;

        // check authorization
        address owner = synPkg.creator;
        if (msg.sender != owner) {
            require(hasRole(ROLE_CREATE, owner, msg.sender), "no permission to create");
        }

        // make sure the extra data is as expected
        synPkg.extraData = "";

        ICrossChain(CROSS_CHAIN).sendSynPackage(
            BUCKET_CHANNEL_ID,
            abi.encodePacked(TYPE_CREATE, abi.encode(synPkg)),
            relayFee,
            _ackRelayFee
        );

        // transfer all the fee to tokenHub
        (bool success, ) = TOKEN_HUB.call{ value: address(this).balance }("");
        require(success, "transfer to tokenHub failed");

        emit CreateSubmitted(owner, msg.sender, synPkg.name);
        return true;
    }

    /**
     * @dev create a bucket and send cross-chain request from BSC to GNFD.
     * Callback function will be called when the request is processed.
     *
     * @param synPkg Package containing information of the bucket to be created
     * @param callbackGasLimit The gas limit for callback function
     * @param extraData Extra data for callback function. The `appAddress` in `extraData` will be ignored.
     * It will be reset to the `msg.sender` all the time. And make sure the `refundAddress` is payable.
     */
    function createBucket(
        CreateBucketSynPackage memory synPkg,
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
        address owner = synPkg.creator;
        if (msg.sender != owner) {
            require(hasRole(ROLE_CREATE, owner, msg.sender), "no permission to create");
        }

        // make sure the extra data is as expected
        extraData.appAddress = msg.sender;
        synPkg.extraData = abi.encode(extraData);

        ICrossChain(CROSS_CHAIN).sendSynPackage(
            BUCKET_CHANNEL_ID,
            abi.encodePacked(TYPE_CREATE, abi.encode(synPkg)),
            relayFee,
            _ackRelayFee
        );

        // transfer all the fee to tokenHub
        (bool success, ) = TOKEN_HUB.call{ value: address(this).balance }("");
        require(success, "transfer to tokenHub failed");

        emit CreateSubmitted(owner, msg.sender, synPkg.name);
        return true;
    }

    /**
     * @dev delete a bucket and send cross-chain request from BSC to GNFD
     *
     * @param id The bucket's id
     */
    function deleteBucket(uint256 id) external payable returns (bool) {
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
            require(hasRole(ROLE_DELETE, owner, msg.sender), "no permission to delete");
        }

        CmnDeleteSynPackage memory synPkg = CmnDeleteSynPackage({ operator: owner, id: id, extraData: "" });

        ICrossChain(CROSS_CHAIN).sendSynPackage(
            BUCKET_CHANNEL_ID,
            abi.encodePacked(TYPE_DELETE, abi.encode(synPkg)),
            relayFee,
            _ackRelayFee
        );

        // transfer all the fee to tokenHub
        (bool success, ) = TOKEN_HUB.call{ value: address(this).balance }("");
        require(success, "transfer to tokenHub failed");

        emit DeleteSubmitted(owner, msg.sender, id);
        return true;
    }

    /**
     * @dev delete a bucket and send cross-chain request from BSC to GNFD.
     * Callback function will be called when the request is processed.
     *
     * @param id The bucket's id
     * @param callbackGasLimit The gas limit for callback function
     * @param extraData Extra data for callback function. The `appAddress` in `extraData` will be ignored.
     * It will be reset to the `msg.sender` all the time. And make sure the `refundAddress` is payable.
     */
    function deleteBucket(
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
            require(hasRole(ROLE_DELETE, owner, msg.sender), "no permission to delete");
        }

        // make sure the extra data is as expected
        extraData.appAddress = msg.sender;
        CmnDeleteSynPackage memory synPkg = CmnDeleteSynPackage({
            operator: owner,
            id: id,
            extraData: abi.encode(extraData)
        });

        ICrossChain(CROSS_CHAIN).sendSynPackage(
            BUCKET_CHANNEL_ID,
            abi.encodePacked(TYPE_DELETE, abi.encode(synPkg)),
            relayFee,
            _ackRelayFee
        );

        // transfer all the fee to tokenHub
        (bool success, ) = TOKEN_HUB.call{ value: address(this).balance }("");
        require(success, "transfer to tokenHub failed");

        emit DeleteSubmitted(owner, msg.sender, id);
        return true;
    }
}
