// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

interface IParamSubscriber {
    function updateParam(string calldata key, bytes calldata value) external;
}
