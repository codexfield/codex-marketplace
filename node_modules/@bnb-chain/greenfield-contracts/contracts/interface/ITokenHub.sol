// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

interface ITokenHub {
    function transferOut(
        address contractAddr,
        address recipient,
        uint256 amount,
        uint64 expireTime
    ) external payable returns (bool);

    function cancelTransferIn(address attacker) external;

    function claimRelayFee(uint256 amount) external returns (uint256);

    function refundCallbackGasFee(address _refundAddress, uint256 _refundFee) external;
}
