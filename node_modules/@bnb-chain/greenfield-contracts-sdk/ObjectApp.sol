// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./BaseApp.sol";
import "./interface/IObjectHub.sol";

abstract contract ObjectApp is BaseApp {
    /*----------------- constants -----------------*/
    uint8 public constant RESOURCE_OBJECT = 0x05;

    /*----------------- storage -----------------*/
    // system contract
    address public objectHub;

    event DeleteObjectSuccess(uint256 indexed tokenId);
    event DeleteObjectFailed(uint32 status, uint256 indexed tokenId);

    /*----------------- initializer -----------------*/
    /**
     * @dev Sets the values for {crossChain}, {callbackGasLimit}, {refundAddress}, {failureHandleStrategy} and {objectHub}.
     */
    function __object_app_init(
        address _crossChain,
        uint256 _callbackGasLimit,
        uint8 _failureHandlerStrategy,
        address _objectHub
    ) internal onlyInitializing {
        __base_app_init_unchained(_crossChain, _callbackGasLimit, _failureHandlerStrategy);
        __object_app_init_unchained(_objectHub);
    }

    function __object_app_init_unchained(address _objectHub) internal onlyInitializing {
        objectHub = _objectHub;
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
        require(msg.sender == objectHub, string.concat("ObjectApp: ", ERROR_INVALID_CALLER));
        require(resourceType == RESOURCE_OBJECT, string.concat("ObjectApp: ", ERROR_INVALID_RESOURCE));

        _objectGreenfieldCall(status, operationType, resourceId, callbackData);
    }

    /*----------------- internal functions -----------------*/
    /**
     * @dev Callback router for object resource.
     * It will call the corresponding callback function according to the operation type.
     */
    function _objectGreenfieldCall(
        uint32 status,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) internal virtual {
        if (operationType == TYPE_DELETE) {
            _deleteObjectCallback(status, resourceId, callbackData);
        } else {
            revert(string.concat("ObjectApp: ", ERROR_INVALID_OPERATION));
        }
    }

    /**
     * @dev Retry the first failed package of this app address in the ObejctHub's queue.
     */
    function _retryObjectPackage() internal virtual {
        IObjectHub(objectHub).retryPackage();
    }

    /**
     * @dev Skip the first failed package of this app address in the ObejctHub's queue.
     */
    function _skipObjectPackage() internal virtual {
        IObjectHub(objectHub).skipPackage();
    }

    /**
     * @dev Send the `deleteObject` transaction to ObjectHub.
     *
     * This function is used for the case that the caller does not need to receive the callback.
     */
    function _deleteObject(uint256 _tokenId) internal virtual {
        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("ObjectApp: ", ERROR_INSUFFICIENT_VALUE));
        IObjectHub(objectHub).deleteObject{value: msg.value}(_tokenId);
    }

    /**
     * @dev Send the `deleteObject` transaction to ObjectHub.
     *
     * This function is used for the case that the caller needs to receive the callback.
     */
    function _deleteObject(
        uint256 _tokenId,
        address _refundAddress,
        CmnStorage.FailureHandleStrategy _failureHandleStrategy,
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
        require(msg.value >= totalFee, string.concat("ObjectApp: ", ERROR_INSUFFICIENT_VALUE));
        IObjectHub(objectHub).deleteObject{value: msg.value}(_tokenId, _callbackGasLimit, _extraData);
    }

    /**
     * @dev Handler for `updateGroup`'s callback.
     */
    function _deleteObjectCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}
}
