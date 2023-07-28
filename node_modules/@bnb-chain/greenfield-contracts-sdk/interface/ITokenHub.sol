// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

/**
 * @dev The interface of CrossChain contract.
 */
interface ITokenHub {
    /**
     * @dev transfer BNB from bsc to greenfield
     */
    function transferOut(
        address contractAddr,
        address recipient,
        uint256 amount,
        uint64 expireTime
    ) external payable returns (bool);
}
