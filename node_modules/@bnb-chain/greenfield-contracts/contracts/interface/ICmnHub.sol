// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

interface ICmnHub {
    function grant(address account, uint32 authCode, uint256 expireTime) external;

    function revoke(address account, uint32 authCode) external;

    function retryPackage() external;

    function skipPackage() external;
}
