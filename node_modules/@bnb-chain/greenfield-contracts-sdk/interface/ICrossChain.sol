// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

/**
 * @dev The interface of CrossChain contract.
 */
interface ICrossChain {
    /**
     * @dev get relayFee and minAckRelayFee.
     * They are the basic fees required for sending cross-chain transactions
     */
    function getRelayFees() external returns (uint256 relayFee, uint256 minAckRelayFee);

    /**
     * @dev get the gas price of the callback transaction
     */
    function callbackGasPrice() external returns (uint256);
}
