// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

interface ILightClient {
    struct InturnRelayer {
        address addr;
        bytes blsKey;
        uint256 start;
        uint256 end;
    }

    function verifyRelayerAndPackage(
        uint64 eventTime,
        bytes calldata _payload,
        bytes calldata _blsSignature,
        uint256 _validatorSet
    ) external view returns (bool verified);

    function isRelayer(address sender) external view returns (bool);
}
