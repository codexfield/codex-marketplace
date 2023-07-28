// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../storage/GroupStorage.sol";

/**
 * @dev The interface of GroupHub contract.
 */
interface IGroupHub {
    /**
     * @dev get the contract address of object token
     */
    function ERC721Token() external view returns (address);

    /**
     * @dev get the contract address of group token
     */
    function ERC1155Token() external view returns (address);

    /**
     * @dev send create group cross-chain transaction
     */
    function createGroup(address creator, string memory name) external payable returns (bool);

    /**
     * @dev send create group cross-chain transaction with callback data
     */
    function createGroup(
        address creator,
        string memory name,
        uint256 callbackGasLimit,
        CmnStorage.ExtraData memory extraData
    ) external payable returns (bool);

    /**
     * @dev send delete group cross-chain transaction
     */
    function deleteGroup(uint256 tokenId) external payable returns (bool);

    /**
     * @dev send delete group cross-chain transaction with callback data
     */
    function deleteGroup(
        uint256 tokenId,
        uint256 callbackGasLimit,
        CmnStorage.ExtraData memory extraData
    ) external payable returns (bool);

    /**
     * @dev send update group cross-chain transaction
     */
    function updateGroup(GroupStorage.UpdateGroupSynPackage memory extraData) external payable returns (bool);

    /**
     * @dev send update group cross-chain transaction with callback data
     */
    function updateGroup(
        GroupStorage.UpdateGroupSynPackage memory createPackage,
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
