// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

interface ITokenHub {
    function claimRelayFee(uint256 amount) external returns (uint256);

    function refundCallbackGasFee(address _refundAddress, uint256 _refundFee) external;

    function cancelTransferIn(address attacker) external;

    function transferOut(address recipient, uint256 amount) external payable returns (bool);
}
