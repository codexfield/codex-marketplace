// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./ICmnHub.sol";
import "../middle-layer/resource-mirror/storage/ObjectStorage.sol";

interface IObjectHub {
    function deleteObject(
        uint256 tokenId,
        uint256 callbackGasLimit,
        CmnStorage.ExtraData memory extraData
    ) external payable returns (bool);
}
