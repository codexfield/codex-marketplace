// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./CmnStorage.sol";

/**
 * @dev Necessary data structures for BucketApp.
 */
contract BucketStorage is CmnStorage {
    /**
     * @dev The data structure of the package for creating a bucket.
     */
    struct CreateBucketSynPackage {
        address creator;
        string name;
        BucketVisibilityType visibility;
        address paymentAddress;
        address primarySpAddress;
        uint256 primarySpApprovalExpiredHeight;
        bytes primarySpSignature;
        uint64 chargedReadQuota;
        bytes extraData;
    }

    enum BucketVisibilityType {
        PublicRead,
        Private,
        Default // If the bucket Visibility is default, it's finally set to private.
    }
}
