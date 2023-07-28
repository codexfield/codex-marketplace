// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../storage/BucketStorage.sol";

/**
 * @dev The interface of BucketHub contract.
 */
interface IBucketHub {
    /**
     * @dev get the contract address of bucket token
     */
    function ERC721Token() external view returns (address);

    /**
     * @dev send create bucket cross-chain transaction
     */
    function createBucket(BucketStorage.CreateBucketSynPackage memory createPackage) external payable returns (bool);

    /**
     * @dev send create bucket cross-chain transaction with callback data
     */
    function createBucket(
        BucketStorage.CreateBucketSynPackage memory createPackage,
        uint256 callbackGasLimit,
        CmnStorage.ExtraData memory extraData
    ) external payable returns (bool);

    /**
     * @dev send delete bucket cross-chain transaction
     */
    function deleteBucket(uint256 tokenId) external payable returns (bool);

    /**
     * @dev send delete bucket cross-chain transaction with callback data
     */
    function deleteBucket(
        uint256 tokenId,
        uint256 callbackGasLimit,
        CmnStorage.ExtraData memory extraData
    ) external payable returns (bool);

    /**
     * @dev to see if an `account` has specific `role` of `granter`
     */
    function hasRole(bytes32 role, address granter, address account) external view returns (bool);

    /**
     * @dev grant an `account` specific role with `expireTime`
     */
    function grant(address account, uint32 authCode, uint256 expireTime) external;

    /**
     * @dev revoke an `account` with specific role
     */
    function revoke(address account, uint32 authCode) external;

    /**
     * @dev retry the first failed package in the queue
     */
    function retryPackage() external;

    /**
     * @dev skip the first failed package in the queue
     */
    function skipPackage() external;
}
