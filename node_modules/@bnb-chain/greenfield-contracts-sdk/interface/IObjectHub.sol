// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../storage/ObjectStorage.sol";

/**
 * @dev The interface of ObjectHub contract.
 */
interface IObjectHub {
    /**
     * @dev get the contract address of object token
     */
    function ERC721Token() external view returns (address);

    /**
     * @dev send create object cross-chain transaction
     */
    function deleteObject(uint256 tokenId) external payable returns (bool);

    /**
     * @dev send create object cross-chain transaction with callback data
     */
    function deleteObject(
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
