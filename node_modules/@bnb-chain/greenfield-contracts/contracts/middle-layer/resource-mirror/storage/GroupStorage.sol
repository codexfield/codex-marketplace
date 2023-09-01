// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./CmnStorage.sol";

contract GroupStorage is CmnStorage {
    /*----------------- constants -----------------*/
    // operation type
    uint8 public constant TYPE_UPDATE = 4;

    // authorization code
    uint32 public constant AUTH_CODE_UPDATE = 4; // 0100

    // role
    bytes32 public constant ROLE_UPDATE = keccak256("ROLE_UPDATE");

    /*----------------- storage -----------------*/
    address public ERC1155Token;

    // BSC to GNFD
    struct CreateGroupSynPackage {
        address creator;
        string name;
        bytes extraData; // abi.encode of ExtraData
    }

    struct UpdateGroupSynPackage {
        address operator;
        uint256 id; // group id
        UpdateGroupOpType opType;
        address[] members;
        bytes extraData; // abi.encode of ExtraData
        uint64[] memberExpiration; // timestamp(UNIX) of member expiration
    }

    // GNFD to BSC
    struct UpdateGroupAckPackage {
        uint32 status;
        uint256 id; // group id
        address operator;
        UpdateGroupOpType opType;
        address[] members;
        bytes extraData; // abi.encode of ExtraData
    }

    enum UpdateGroupOpType {
        AddMembers,
        RemoveMembers,
        RenewMembers
    }

    event UpdateSubmitted(address owner, address operator, uint256 id, uint8 opType, address[] members);
    event UpdateSuccess(address indexed operator, uint256 indexed id, uint8 opType);
    event UpdateFailed(address indexed operator, uint256 indexed id, uint8 opType);

    // PlaceHolder reserve for future usage
    uint256[50] private __reservedGroupStorageSlots;
}
