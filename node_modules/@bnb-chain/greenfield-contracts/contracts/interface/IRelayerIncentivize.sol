// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

interface IRelayerIncentivize {
    function addReward(
        address payable headerRelayerAddr,
        address payable packageRelayer,
        uint256 amount,
        bool fromSystemReward
    ) external returns (bool);
}
