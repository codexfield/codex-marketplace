// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

interface IAccessControl {
    function hasRole(bytes32 role, address granter, address account) external view returns (bool);

    function grantRole(bytes32 role, address grantee, uint256 expireTime) external;

    function revokeRole(bytes32 role, address account) external;

    function renounceRole(bytes32 role, address granter) external;
}
