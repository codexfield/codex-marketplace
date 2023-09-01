// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./Config.sol";
import "./interface/ILightClient.sol";
import "./lib/Memory.sol";
import "./lib/BytesToTypes.sol";
import "./lib/BytesLib.sol";

contract GnfdLightClient is Initializable, Config, ILightClient {
    struct Validator {
        bytes32 pubKey;
        int64 votingPower;
        address relayerAddress;
        bytes relayerBlsKey;
    }

    /* --------------------- 1. constant --------------------- */
    address public constant PACKAGE_VERIFY_CONTRACT = address(0x0000000000000000000000000000000000000066);
    address public constant HEADER_VALIDATE_CONTRACT = address(0x0000000000000000000000000000000000000067);

    uint256 public constant CHAIN_ID_LENGTH = 32;
    uint256 public constant HEIGHT_LENGTH = 8;
    uint256 public constant VALIDATOR_SET_HASH_LENGTH = 32;
    uint256 public constant CONSENSUS_STATE_BYTES_LENGTH = 32;
    uint256 public constant CONSENSUS_STATE_BASE_LENGTH = CHAIN_ID_LENGTH + HEIGHT_LENGTH + VALIDATOR_SET_HASH_LENGTH;

    uint256 public constant VALIDATOR_PUB_KEY_LENGTH = 32;
    uint256 public constant VALIDATOR_VOTING_POWER_LENGTH = 8;
    uint256 public constant RELAYER_ADDRESS_LENGTH = 20;
    uint256 public constant RELAYER_BLS_KEY_LENGTH = 48;

    uint256 public constant VALIDATOR_BYTES_LENGTH =
        VALIDATOR_PUB_KEY_LENGTH + VALIDATOR_VOTING_POWER_LENGTH + RELAYER_ADDRESS_LENGTH + RELAYER_BLS_KEY_LENGTH;
    uint256 public constant MESSAGE_HASH_LENGTH = 32;
    uint256 public constant BLS_SIGNATURE_LENGTH = 96;

    /* --------------------- 2. storage --------------------- */
    bytes32 public chainID;
    uint64 public gnfdHeight;
    bytes32 public nextValidatorSetHash;
    bytes public consensusStateBytes;

    uint256 public inTurnRelayerRelayInterval;
    uint256 public inTurnRelayerValidityPeriod;

    Validator[] public validatorSet;
    mapping(address => bool) public isRelayer;
    mapping(uint64 => address payable) public submitters;
    /* --------------------- 3. events ----------------------- */

    event InitConsensusState(uint64 height);
    event UpdatedConsensusState(uint64 height, bool validatorSetChanged);
    event ParamChange(string key, bytes value);

    /* --------------------- 4. functions -------------------- */
    modifier onlyRelayer() {
        require(isRelayer[msg.sender], "only relayer");
        _;
    }

    function initialize(bytes calldata _initConsensusStateBytes) public initializer {
        uint256 ptr;
        uint256 len;
        bytes32 tmpChainID;

        (ptr, len) = Memory.fromBytes(_initConsensusStateBytes);
        assembly {
            tmpChainID := mload(ptr)
        }

        chainID = tmpChainID;
        updateConsensusState(ptr, len, true, 0);
        consensusStateBytes = _initConsensusStateBytes;

        inTurnRelayerRelayInterval = 600 seconds;
        inTurnRelayerValidityPeriod = 30 seconds;

        emit InitConsensusState(gnfdHeight);
    }

    // TODO we will optimize the gas consumption here.
    function syncLightBlock(bytes calldata _lightBlock, uint64 _height) external onlyRelayer returns (bool) {
        require(submitters[_height] == address(0x0), "can't sync duplicated header");
        require(_height > gnfdHeight, "can't sync header before latest height");

        bytes memory input = abi.encodePacked(abi.encode(consensusStateBytes.length), consensusStateBytes);
        bytes memory tmpBlock = _lightBlock;
        input = abi.encodePacked(input, tmpBlock);
        (bool success, bytes memory result) = HEADER_VALIDATE_CONTRACT.staticcall(input);
        require(success && result.length > 0, "header validate failed");

        uint256 ptr = Memory.dataPtr(result);
        uint256 tmp;
        assembly {
            tmp := mload(ptr)
        }

        bool validatorSetChanged = (tmp >> 248) != 0x00;
        uint256 consensusStateLength = tmp & 0xffffffffffffffff;
        ptr = ptr + CONSENSUS_STATE_BYTES_LENGTH;

        updateConsensusState(ptr, consensusStateLength, validatorSetChanged, _height);

        submitters[_height] = payable(msg.sender);
        if (validatorSetChanged) {
            consensusStateBytes = BytesLib.slice(result, 32, consensusStateLength);
        }

        emit UpdatedConsensusState(_height, validatorSetChanged);

        return true;
    }

    function verifyPackage(
        bytes calldata _payload,
        bytes calldata _blsSignature,
        uint256 _validatorSetBitMap
    ) public view returns (bool) {
        require(_blsSignature.length == BLS_SIGNATURE_LENGTH, "invalid signature length");

        uint256 bitCount;
        bytes32 msgHash = keccak256(_payload);
        bytes memory tmpBlsSig = _blsSignature;
        bytes memory input = abi.encodePacked(abi.encode(msgHash), tmpBlsSig);
        for (uint256 i = 0; i < validatorSet.length; i++) {
            if ((_validatorSetBitMap & (0x1 << i)) != 0) {
                bitCount++;
                input = abi.encodePacked(input, validatorSet[i].relayerBlsKey);
            }
        }
        require(bitCount > (validatorSet.length * 2) / 3, "no majority validators");

        (bool success, bytes memory result) = PACKAGE_VERIFY_CONTRACT.staticcall(input);
        return success && result.length > 0;
    }

    function verifyRelayerAndPackage(
        uint64 eventTime,
        bytes calldata _payload,
        bytes calldata _blsSignature,
        uint256 _validatorSetBitMap
    ) external view onlyCrossChain returns (bool) {
        require(isRelayer[tx.origin], "tx origin is not relayer");

        InturnRelayer memory inturnRelayer = getInturnRelayerWithInterval();
        if (tx.origin != inturnRelayer.addr) {
            require(block.timestamp - eventTime > inTurnRelayerValidityPeriod, "invalid candidate relayer");
        }

        return verifyPackage(_payload, _blsSignature, _validatorSetBitMap);
    }

    function getRelayers() external view returns (address[] memory) {
        address[] memory relayers = new address[](validatorSet.length);
        for (uint256 i = 0; i < validatorSet.length; i++) {
            relayers[i] = validatorSet[i].relayerAddress;
        }
        return relayers;
    }

    function blsPubKeys() external view returns (bytes memory _blsPubKeys) {
        _blsPubKeys = bytes("");
        for (uint256 i = 0; i < validatorSet.length; i++) {
            _blsPubKeys = abi.encodePacked(_blsPubKeys, validatorSet[i].relayerBlsKey);
        }
    }

    function getInturnRelayer() external view returns (InturnRelayer memory relayer) {
        return getInturnRelayerWithInterval();
    }

    function getInturnRelayerWithInterval() private view returns (InturnRelayer memory relayer) {
        uint256 relayerSize = validatorSet.length;
        uint256 totalInterval = inTurnRelayerRelayInterval * relayerSize;
        uint256 curTs = block.timestamp;
        uint256 remainder = curTs % totalInterval;
        uint256 inTurnRelayerIndex = remainder / inTurnRelayerRelayInterval;
        uint256 start = curTs - (remainder - inTurnRelayerIndex * inTurnRelayerRelayInterval);

        relayer.start = start;
        relayer.end = start + inTurnRelayerRelayInterval;
        relayer.blsKey = validatorSet[inTurnRelayerIndex].relayerBlsKey;
        relayer.addr = validatorSet[inTurnRelayerIndex].relayerAddress;
        return relayer;
    }

    function getInturnRelayerBlsPubKey() external view returns (bytes memory) {
        InturnRelayer memory relayer = getInturnRelayerWithInterval();
        return relayer.blsKey;
    }

    function getInturnRelayerAddress() external view returns (address) {
        InturnRelayer memory relayer = getInturnRelayerWithInterval();
        return relayer.addr;
    }

    // TODO we will optimize the gas consumption here.
    // input:
    // | chainID   | height   | nextValidatorSetHash | [{validator pubkey, voting power, relayer address, relayer bls pubkey}] |
    // | 32 bytes  | 8 bytes  | 32 bytes             | [{32 bytes, 8 bytes, 20 bytes, 48 bytes}]                               |
    function updateConsensusState(uint256 ptr, uint256 size, bool validatorSetChanged, uint64 expectHeight) internal {
        require(size > CONSENSUS_STATE_BASE_LENGTH, "cs length too short");
        require((size - CONSENSUS_STATE_BASE_LENGTH) % VALIDATOR_BYTES_LENGTH == 0, "invalid cs length");

        ptr = ptr + HEIGHT_LENGTH;
        uint64 tmpHeight;
        assembly {
            tmpHeight := mload(ptr)
        }

        if (expectHeight > 0) {
            require(tmpHeight == expectHeight, "height mismatch");
        }
        gnfdHeight = tmpHeight;

        ptr = ptr + VALIDATOR_SET_HASH_LENGTH;
        assembly {
            sstore(nextValidatorSetHash.slot, mload(ptr))
        }

        if (!validatorSetChanged) {
            return;
        }

        ptr = ptr + CHAIN_ID_LENGTH;
        uint256 valNum = (size - CONSENSUS_STATE_BASE_LENGTH) / VALIDATOR_BYTES_LENGTH;

        for (uint256 idx = 0; idx < validatorSet.length; idx++) {
            delete isRelayer[validatorSet[idx].relayerAddress];
        }
        Validator[] memory newValidatorSet = new Validator[](valNum);
        for (uint256 idx = 0; idx < valNum; idx++) {
            newValidatorSet[idx] = decodeValidator(ptr);
            isRelayer[newValidatorSet[idx].relayerAddress] = true;
            ptr = ptr + VALIDATOR_BYTES_LENGTH;
        }

        uint256 i = 0;
        uint256 curValidatorSetLen = validatorSet.length;
        for (i = 0; i < valNum && i < curValidatorSetLen; i++) {
            validatorSet[i] = newValidatorSet[i];
        }
        for (; i < curValidatorSetLen; i++) {
            validatorSet.pop();
        }
        for (; i < valNum; i++) {
            validatorSet.push(newValidatorSet[i]);
        }
    }

    function decodeValidator(uint256 ptr) internal pure returns (Validator memory val) {
        bytes32 tmpPubKey;
        assembly {
            tmpPubKey := mload(ptr)
        }
        val.pubKey = tmpPubKey;

        ptr = ptr + VALIDATOR_VOTING_POWER_LENGTH;
        int64 tmpVotingPower;
        assembly {
            tmpVotingPower := mload(ptr)
        }
        val.votingPower = tmpVotingPower;

        ptr = ptr + RELAYER_ADDRESS_LENGTH;
        address tmpRelayerAddress;
        assembly {
            tmpRelayerAddress := mload(ptr)
        }
        val.relayerAddress = tmpRelayerAddress;

        ptr = ptr + VALIDATOR_PUB_KEY_LENGTH;
        val.relayerBlsKey = Memory.toBytes(ptr, RELAYER_BLS_KEY_LENGTH);
        return val;
    }

    function versionInfo()
        external
        pure
        override
        returns (uint256 version, string memory name, string memory description)
    {
        return (400_001, "GnfdLightClient", "init version");
    }

    function updateParam(string calldata key, bytes calldata value) external onlyGov {
        uint256 valueLength = value.length;
        if (_compareStrings(key, "inTurnRelayerRelayInterval")) {
            require(valueLength == 32, "length of value for inTurnRelayerRelayInterval should be 32");
            uint256 newInTurnRelayerRelayInterval = BytesToTypes.bytesToUint256(valueLength, value);
            require(
                newInTurnRelayerRelayInterval >= 300 && newInTurnRelayerRelayInterval <= 1800,
                "the newInTurnRelayerRelayInterval should be [300, 1800 seconds] "
            );
            inTurnRelayerRelayInterval = newInTurnRelayerRelayInterval;
        } else if (_compareStrings(key, "inTurnRelayerValidityPeriod")) {
            require(valueLength == 32, "length of value for inTurnRelayerValidityPeriod should be 32");
            uint256 newInTurnRelayerValidityPeriod = BytesToTypes.bytesToUint256(valueLength, value);
            require(
                newInTurnRelayerValidityPeriod >= 20 && newInTurnRelayerValidityPeriod <= 100,
                "the newInTurnRelayerValidityPeriod should be [20, 100 seconds] "
            );
            inTurnRelayerValidityPeriod = newInTurnRelayerValidityPeriod;
        } else {
            revert("unknown param");
        }
        emit ParamChange(key, value);
    }
}
