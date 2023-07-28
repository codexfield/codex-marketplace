// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./BaseApp.sol";
import "./interface/IBucketHub.sol";

/**
 * @dev Contract module that allows children to interact with the
 * BucketHub easily.
 */
abstract contract BucketApp is BaseApp {
    /*----------------- constants -----------------*/
    // Bucket's resource code
    uint8 public constant RESOURCE_BUCKET = 0x04;

    /*----------------- storage -----------------*/
    // system contract
    address public bucketHub;

    // payment address for resource creation
    address public paymentAddress;

    event CreateBucketSuccess(bytes bucketName, uint256 indexed tokenId);
    event CreateBucketFailed(uint32 status, bytes bucketName);
    event DeleteBucketSuccess(uint256 indexed tokenId);
    event DeleteBucketFailed(uint32 status, uint256 indexed tokenId);

    /*----------------- initializer -----------------*/
    /**
     * @dev Sets the values for {crossChain}, {callbackGasLimit}, {refundAddress}, {failureHandleStrategy},
     * {bucketHub} and {paymentAddress}.
     */
    function __bucket_app_init(
        address _crossChain,
        uint256 _callbackGasLimit,
        uint8 _failureHandlerStrategy,
        address _bucketHub,
        address _paymentAddress
    ) internal onlyInitializing {
        __base_app_init_unchained(_crossChain, _callbackGasLimit, _failureHandlerStrategy);
        __bucket_app_init_unchained(_bucketHub, _paymentAddress);
    }

    function __bucket_app_init_unchained(address _bucketHub, address _paymentAddress) internal onlyInitializing {
        bucketHub = _bucketHub;
        paymentAddress = _paymentAddress;
    }

    /*----------------- external functions -----------------*/
    /**
     * @dev See {BaseApp-greenfieldCall}
     */
    function greenfieldCall(
        uint32 status,
        uint8 resourceType,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external virtual override {
        require(msg.sender == bucketHub, string.concat("BucketApp: ", ERROR_INVALID_CALLER));
        require(resourceType == RESOURCE_BUCKET, string.concat("BucketApp: ", ERROR_INVALID_RESOURCE));

        _bucketGreenfieldCall(status, operationType, resourceId, callbackData);
    }

    /*----------------- internal functions -----------------*/
    /**
     * @dev Callback router for bucket resource.
     * It will call the corresponding callback function according to the operation type.
     */
    function _bucketGreenfieldCall(
        uint32 status,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) internal virtual {
        if (operationType == TYPE_CREATE) {
            _createBucketCallback(status, resourceId, callbackData);
        } else if (operationType == TYPE_DELETE) {
            _deleteBucketCallback(status, resourceId, callbackData);
        } else {
            revert(string.concat("BucketApp: ", ERROR_INVALID_OPERATION));
        }
    }

    /**
     * @dev Retry the first failed package of this app address in the BucketHub's queue.
     */
    function _retryBucketPackage() internal virtual {
        IBucketHub(bucketHub).retryPackage();
    }

    /**
     * @dev Skip the first failed package of this app address in the BucketHub's queue.
     */
    function _skipBucketPackage() internal virtual {
        IBucketHub(bucketHub).skipPackage();
    }

    /**
     * @dev Set `paymentAddress`.
     */
    function _setPaymentAddress(address _paymentAddress) internal virtual {
        paymentAddress = _paymentAddress;
    }

    /**
     * @dev Assemble a `BucketStorage.CreateBucketSynPackage` from provided elements
     * and send the transaction to BucketHub.
     *
     * This function is used for the case that the caller does not need to receive the callback.
     */
    function _createBucket(
        address _creator,
        string memory _name,
        BucketStorage.BucketVisibilityType _visibility,
        uint64 _chargedReadQuota,
        address _spAddress,
        uint256 _expireHeight,
        bytes calldata _sig
    ) internal virtual {
        BucketStorage.CreateBucketSynPackage memory createPkg = BucketStorage.CreateBucketSynPackage({
            creator: _creator,
            name: _name,
            visibility: _visibility,
            paymentAddress: paymentAddress,
            primarySpAddress: _spAddress,
            primarySpApprovalExpiredHeight: _expireHeight,
            primarySpSignature: _sig,
            chargedReadQuota: _chargedReadQuota,
            extraData: ""
        });

        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("BucketApp: ", ERROR_INSUFFICIENT_VALUE));
        IBucketHub(bucketHub).createBucket{value: msg.value}(createPkg);
    }

    /**
     * @dev Assemble a `BucketStorage.CreateBucketSynPackage` from provided elements
     * and send the transaction to BucketHub.
     *
     * This function is used for the case that the caller needs to receive the callback.
     */
    function _createBucket(
        address _creator,
        string memory _name,
        BucketStorage.BucketVisibilityType _visibility,
        address _paymentAddress,
        address _spAddress,
        uint256 _expireHeight,
        bytes calldata _sig,
        uint64 _chargedReadQuota,
        address _refundAddress,
        CmnStorage.FailureHandleStrategy _failureHandleStrategy,
        bytes memory _callbackData,
        uint256 _callbackGasLimit
    ) internal virtual {
        BucketStorage.CreateBucketSynPackage memory createPkg = BucketStorage.CreateBucketSynPackage({
            creator: _creator,
            name: _name,
            visibility: _visibility,
            paymentAddress: _paymentAddress,
            primarySpAddress: _spAddress,
            primarySpApprovalExpiredHeight: _expireHeight,
            primarySpSignature: _sig,
            chargedReadQuota: _chargedReadQuota,
            extraData: ""
        });

        CmnStorage.ExtraData memory _extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: _refundAddress,
            failureHandleStrategy: _failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("BucketApp: ", ERROR_INSUFFICIENT_VALUE));
        IBucketHub(bucketHub).createBucket{value: msg.value}(createPkg, _callbackGasLimit, _extraData);
    }

    /**
     * @dev Send the `deleteBucket` transaction to BucketHub.
     *
     * This function is used for the case that the caller does not need to receive the callback.
     */
    function _deleteBucket(uint256 _tokenId) internal virtual {
        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("BucketApp: ", ERROR_INSUFFICIENT_VALUE));
        IBucketHub(bucketHub).deleteBucket{value: msg.value}(_tokenId);
    }

    /**
     * @dev Send the `deleteBucket` transaction to BucketHub.
     *
     * This function is used for the case that the caller needs to receive the callback.
     */
    function _deleteBucket(
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
        require(msg.value >= totalFee, string.concat("BucketApp: ", ERROR_INSUFFICIENT_VALUE));
        IBucketHub(bucketHub).deleteBucket{value: msg.value}(_tokenId, _callbackGasLimit, _extraData);
    }

    /**
     * @dev Handler for `createBucket`'s callback.
     */
    function _createBucketCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}

    /**
     * @dev Handler for `deleteBucket`'s callback.
     */
    function _deleteBucketCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}
}
