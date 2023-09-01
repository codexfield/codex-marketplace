// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@bnb-chain/greenfield-contracts/contracts/interface/ICmnHub.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IGroupHub.sol";

import "./BaseApp.sol";

abstract contract GroupApp is BaseApp, GroupStorage {
    /*----------------- constants -----------------*/
    // Group's resource code
    uint8 public constant RESOURCE_GROUP = 0x06;

    /*----------------- storage -----------------*/
    // system contract
    address public groupHub;

    event CreateGroupSuccess(bytes groupName, uint256 indexed tokenId);
    event CreateGroupFailed(uint32 status, bytes groupName);
    event DeleteGroupSuccess(uint256 indexed tokenId);
    event DeleteGroupFailed(uint32 status, uint256 indexed tokenId);
    event UpdateGroupSuccess(uint256 indexed tokenId);
    event UpdateGroupFailed(uint32 status, uint256 indexed tokenId);

    /*----------------- initializer -----------------*/
    /**
     * @dev Sets the values for {crossChain}, {callbackGasLimit}, {refundAddress}, {failureHandleStrategy} and {groupHub}.
     */
    function __group_app_init(
        address _crossChain,
        uint256 _callbackGasLimit,
        uint8 _failureHandlerStrategy,
        address _groupHub
    ) internal onlyInitializing {
        __base_app_init_unchained(_crossChain, _callbackGasLimit, _failureHandlerStrategy);
        __group_app_init_unchained(_groupHub);
    }

    function __group_app_init_unchained(address _groupHub) internal onlyInitializing {
        groupHub = _groupHub;
    }

    /*----------------- external functions -----------------*/
    /**
     * @dev see {BaseApp-greenfieldCall}
     */
    function greenfieldCall(
        uint32 status,
        uint8 resourceType,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external virtual override {
        require(msg.sender == groupHub, string.concat("GroupApp: ", ERROR_INVALID_CALLER));
        require(resourceType == RESOURCE_GROUP, string.concat("GroupApp: ", ERROR_INVALID_RESOURCE));

        _groupGreenfieldCall(status, operationType, resourceId, callbackData);
    }

    /*----------------- internal functions -----------------*/
    /**
     * @dev Callback router for group resource.
     * It will call the corresponding callback function according to the operation type.
     */
    function _groupGreenfieldCall(
        uint32 status,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) internal virtual {
        if (operationType == TYPE_CREATE) {
            _createGroupCallback(status, resourceId, callbackData);
        } else if (operationType == TYPE_DELETE) {
            _deleteGroupCallback(status, resourceId, callbackData);
        } else if (operationType == TYPE_UPDATE) {
            _updateGroupCallback(status, resourceId, callbackData);
        } else {
            revert(string.concat("GroupApp: ", ERROR_INVALID_OPERATION));
        }
    }

    /**
     * @dev Retry the first failed package of this app address in the GroupHub's queue.
     */
    function _retryGroupPackage() internal virtual {
        ICmnHub(groupHub).retryPackage();
    }

    /**
     * @dev Skip the first failed package of this app address in the GroupHub's queue.
     */
    function _skipGroupPackage() internal virtual {
        ICmnHub(groupHub).skipPackage();
    }

    /**
     * @dev Send the `createGroup` transaction to GroupHub.
     *
     * This function is used for the case that the caller does not need to receive the callback.
     */
    function _createGroup(address _owner, string memory _groupName) internal virtual {
        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("GroupApp: ", ERROR_INSUFFICIENT_VALUE));
        IGroupHub(groupHub).createGroup{value: msg.value}(_owner, _groupName);
    }

    /**
     * @dev Send the `createGroup` transaction to GroupHub.
     *
     * This function is used for the case that the caller needs to receive the callback.
     */
    function _createGroup(
        address _refundAddress,
        PackageQueue.FailureHandleStrategy _failureHandleStrategy,
        bytes memory _callbackData,
        address _owner,
        string memory _groupName,
        uint256 _callbackGasLimit
    ) internal virtual {
        CmnStorage.ExtraData memory _extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: _refundAddress,
            failureHandleStrategy: _failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("GroupApp: ", ERROR_INSUFFICIENT_VALUE));
        IGroupHub(groupHub).createGroup{value: msg.value}(_owner, _groupName, _callbackGasLimit, _extraData);
    }

    /**
     * @dev Send the `deleteGroup` transaction to GroupHub.
     *
     * This function is used for the case that the caller does not need to receive the callback.
     */
    function _deleteGroup(uint256 _tokenId) internal virtual {
        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("GroupApp: ", ERROR_INSUFFICIENT_VALUE));
        IGroupHub(groupHub).deleteGroup{value: msg.value}(_tokenId);
    }

    /**
     * @dev Send the `deleteGroup` transaction to GroupHub.
     *
     * This function is used for the case that the caller needs to receive the callback.
     */
    function _deleteGroup(
        uint256 _tokenId,
        address _refundAddress,
        PackageQueue.FailureHandleStrategy _failureHandleStrategy,
        bytes memory _callbackData,
        uint256 _callbackGasLimit
    ) internal virtual {
        CmnStorage.ExtraData memory _extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: _refundAddress,
            failureHandleStrategy: _failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("GroupApp: ", ERROR_INSUFFICIENT_VALUE));
        IGroupHub(groupHub).deleteGroup{value: msg.value}(_tokenId, _callbackGasLimit, _extraData);
    }

    /**
     * @dev Assemble a `GroupStorage.UpdateGroupSynPackage` from provided elements
     * and send the transaction to GroupHub.
     *
     * This function is used for the case that the caller does not need to receive the callback.
     */
    function _updateGroup(
        address _owner,
        uint256 _tokenId,
        GroupStorage.UpdateGroupOpType _opType,
        address[] memory _members,
        uint64[] memory _expiration
    ) internal virtual {
        GroupStorage.UpdateGroupSynPackage memory updatePkg = GroupStorage.UpdateGroupSynPackage({
            operator: _owner,
            id: _tokenId,
            opType: _opType,
            members: _members,
            extraData: "",
            memberExpiration: _expiration
        });

        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("GroupApp: ", ERROR_INSUFFICIENT_VALUE));
        IGroupHub(groupHub).updateGroup{value: msg.value}(updatePkg);
    }

    /**
     * @dev Assemble a `GroupStorage.UpdateGroupSynPackage` from provided elements
     * and send the transaction to GroupHub.
     *
     * This function is used for the case that the caller needs to receive the callback.
     */
    function _updateGroup(
        address _owner,
        uint256 _tokenId,
        GroupStorage.UpdateGroupOpType _opType,
        address[] memory _members,
        uint64[] memory _expiration,
        address _refundAddress,
        PackageQueue.FailureHandleStrategy _failureHandleStrategy,
        bytes memory _callbackData,
        uint256 _callbackGasLimit
    ) internal virtual {
        GroupStorage.UpdateGroupSynPackage memory updatePkg = GroupStorage.UpdateGroupSynPackage({
            operator: _owner,
            id: _tokenId,
            opType: _opType,
            members: _members,
            extraData: "",
            memberExpiration: _expiration
        });

        CmnStorage.ExtraData memory _extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: _refundAddress,
            failureHandleStrategy: _failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("GroupApp: ", ERROR_INSUFFICIENT_VALUE));
        IGroupHub(groupHub).updateGroup{value: msg.value}(updatePkg, _callbackGasLimit, _extraData);
    }

    /**
     * @dev Handler for `createGroup`'s callback.
     */
    function _createGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}

    /**
     * @dev Handler for `deleteGroup`'s callback.
     */
    function _deleteGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}

    /**
     * @dev Handler for `updateGroup`'s callback.
     */
    function _updateGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}

    // PlaceHolder reserve for future use
    uint256[50] private __reservedCmnStorageSlots;
}
