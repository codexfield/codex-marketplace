// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interface/IMiddleLayer.sol";
import "./interface/ITokenHub.sol";
import "./interface/ILightClient.sol";
import "./interface/IRelayerHub.sol";
import "./lib/BytesToTypes.sol";
import "./Config.sol";
import "./interface/ICrossChain.sol";

contract CrossChain is Config, Initializable, ICrossChain {
    /*----------------- constants -----------------*/
    uint8 public constant SYN_PACKAGE = 0x00;
    uint8 public constant ACK_PACKAGE = 0x01;
    uint8 public constant FAIL_ACK_PACKAGE = 0x02;

    // 0xebbda044f67428d7e9b472f9124983082bcda4f84f5148ca0a9ccbe06350f196
    bytes32 public constant SUSPEND_PROPOSAL = keccak256("SUSPEND_PROPOSAL");
    // 0xcf82004e82990eca84a75e16ba08aa620238e076e0bc7fc4c641df44bbf5b55a
    bytes32 public constant REOPEN_PROPOSAL = keccak256("REOPEN_PROPOSAL");
    // 0x605b57daa79220f76a5cdc8f5ee40e59093f21a4e1cec30b9b99c555e94c75b9
    bytes32 public constant CANCEL_TRANSFER_PROPOSAL = keccak256("CANCEL_TRANSFER_PROPOSAL");
    // 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
    bytes32 public constant EMPTY_CONTENT_HASH = keccak256("");
    uint256 public constant EMERGENCY_PROPOSAL_EXPIRE_PERIOD = 1 hours;
    uint256 public constant MAX_RELAY_FEE = 1 ether;
    /*----------------- storage layer -----------------*/
    bool public isSuspended;
    // proposal type hash => latest emergency proposal
    mapping(bytes32 => EmergencyProposal) public emergencyProposals;
    // proposal type hash => the threshold of proposal approved
    mapping(bytes32 => uint16) public quorumMap;

    uint256 public relayFee;
    uint256 public minAckRelayFee;
    uint16 public chainId;
    uint16 public gnfdChainId;
    uint256 public batchSizeForOracle;
    uint256 public callbackGasPrice;
    uint256 public previousTxHeight;
    uint256 public txCounter;
    int64 public oracleSequence;
    mapping(uint8 => address) public channelHandlerMap;
    mapping(address => mapping(uint8 => bool)) public registeredContractChannelMap;
    mapping(uint8 => uint64) public channelSendSequenceMap;
    mapping(uint8 => uint64) public channelReceiveSequenceMap;

    /*----------------- struct / event / modifier -----------------*/
    struct EmergencyProposal {
        uint16 quorum;
        uint128 expiredAt;
        bytes32 contentHash;
        address[] approvers;
    }

    event ProposalSubmitted(
        bytes32 indexed proposalTypeHash,
        address indexed proposer,
        uint128 quorum,
        uint128 expiredAt,
        bytes32 contentHash
    );
    event Suspended(address indexed executor);
    event Reopened(address indexed executor);
    event CrossChainPackage(
        uint32 srcChainId,
        uint32 dstChainId,
        uint64 indexed oracleSequence,
        uint64 indexed packageSequence,
        uint8 indexed channelId,
        bytes payload
    );
    event ReceivedPackage(uint8 packageType, uint64 indexed packageSequence, uint8 indexed channelId);
    event UnsupportedPackage(uint64 indexed packageSequence, uint8 indexed channelId, bytes payload);
    event UnexpectedRevertInPackageHandler(address indexed contractAddr, string reason);
    event UnexpectedFailureAssertionInPackageHandler(address indexed contractAddr, bytes lowLevelData);
    event ParamChange(string key, bytes value);
    event EnableOrDisableChannel(uint8 indexed channelId, bool isEnable);
    event AddChannel(uint8 indexed channelId, address indexed contractAddr);

    modifier onlyRegisteredContractChannel(uint8 channelId) {
        require(
            registeredContractChannelMap[msg.sender][channelId],
            "the contract and channel have not been registered"
        );
        _;
    }

    modifier whenNotSuspended() {
        require(!isSuspended, "suspended");
        _;
    }

    modifier whenSuspended() {
        require(isSuspended, "not suspended");
        _;
    }

    modifier onlyRelayer() {
        require(ILightClient(LIGHT_CLIENT).isRelayer(msg.sender), "only relayer");
        _;
    }

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "only EOA");
        _;
    }

    modifier relayFeeCheck(uint256 _relayFee, uint256 _ackRelayFee) {
        require(_relayFee <= MAX_RELAY_FEE, "_relayFee too large");
        require(_ackRelayFee <= MAX_RELAY_FEE, "_ackRelayFee too large");
        _;
    }

    /*----------------- external function -----------------*/
    function initialize(uint16 _gnfdChainId) public initializer {
        require(_gnfdChainId != 0, "zero _gnfdChainId");
        require(PROXY_ADMIN != address(0), "zero PROXY_ADMIN");
        require(GOV_HUB != address(0), "zero GOV_HUB");
        require(CROSS_CHAIN != address(0), "zero CROSS_CHAIN");
        require(TOKEN_HUB != address(0), "zero TOKEN_HUB");
        require(LIGHT_CLIENT != address(0), "zero LIGHT_CLIENT");
        require(RELAYER_HUB != address(0), "zero RELAYER_HUB");
        require(BUCKET_HUB != address(0), "zero BUCKET_HUB");
        require(OBJECT_HUB != address(0), "zero OBJECT_HUB");
        require(GROUP_HUB != address(0), "zero GROUP_HUB");
        require(block.chainid <= type(uint16).max, "chain id overflow");

        relayFee = 25 * 1e13;
        minAckRelayFee = 130 * 1e13;

        chainId = uint16(block.chainid);
        gnfdChainId = _gnfdChainId;

        // TODO register other channels
        channelHandlerMap[TRANSFER_IN_CHANNEL_ID] = TOKEN_HUB;
        registeredContractChannelMap[TOKEN_HUB][TRANSFER_IN_CHANNEL_ID] = true;

        channelHandlerMap[TRANSFER_OUT_CHANNEL_ID] = TOKEN_HUB;
        registeredContractChannelMap[TOKEN_HUB][TRANSFER_OUT_CHANNEL_ID] = true;

        channelHandlerMap[GOV_CHANNEL_ID] = GOV_HUB;
        registeredContractChannelMap[GOV_HUB][GOV_CHANNEL_ID] = true;

        channelHandlerMap[BUCKET_CHANNEL_ID] = BUCKET_HUB;
        registeredContractChannelMap[BUCKET_HUB][BUCKET_CHANNEL_ID] = true;

        channelHandlerMap[OBJECT_CHANNEL_ID] = OBJECT_HUB;
        registeredContractChannelMap[OBJECT_HUB][OBJECT_CHANNEL_ID] = true;

        channelHandlerMap[GROUP_CHANNEL_ID] = GROUP_HUB;
        registeredContractChannelMap[GROUP_HUB][GROUP_CHANNEL_ID] = true;

        callbackGasPrice = 6 gwei;
        batchSizeForOracle = 50;

        oracleSequence = -1;
        previousTxHeight = 0;
        txCounter = 0;
        quorumMap[SUSPEND_PROPOSAL] = 2;
        quorumMap[REOPEN_PROPOSAL] = 2;
        quorumMap[CANCEL_TRANSFER_PROPOSAL] = 2;
    }

    function encodePayload(
        uint8 packageType,
        uint256 _relayFee,
        uint256 _ackRelayFee,
        bytes memory msgBytes
    ) public view relayFeeCheck(_relayFee, _ackRelayFee) returns (bytes memory) {
        return
            packageType == SYN_PACKAGE
                ? abi.encodePacked(packageType, uint64(block.timestamp), _relayFee, _ackRelayFee, msgBytes)
                : abi.encodePacked(packageType, uint64(block.timestamp), _relayFee, msgBytes);
    }

    function handlePackage(
        bytes calldata _payload,
        bytes calldata _blsSignature,
        uint256 _validatorsBitSet
    ) external whenNotSuspended onlyEOA {
        // 1. decode _payload
        // 1-1 check if the chainId is valid
        (
            bool success,
            uint8 channelId,
            uint64 sequence,
            uint8 packageType,
            uint64 eventTime,
            uint256 _maxRelayFee,
            uint256 _ackRelayFee,
            bytes memory packageLoad
        ) = _checkPayload(_payload);
        if (!success) {
            emit UnsupportedPackage(sequence, channelId, _payload);
            return;
        }
        emit ReceivedPackage(packageType, sequence, channelId);

        // 1-2 check if the channel is supported
        require(channelHandlerMap[channelId] != address(0), "channel is not supported");
        // 1-3 check if the sequence is in order
        require(sequence == channelReceiveSequenceMap[channelId], "sequence not in order");
        channelReceiveSequenceMap[channelId]++;

        // 2. check valid relayer And 3. verify bls signature
        require(
            ILightClient(LIGHT_CLIENT).verifyRelayerAndPackage(eventTime, _payload, _blsSignature, _validatorsBitSet),
            "cross chain package not verified"
        );

        // 4. handle package
        address _handler = channelHandlerMap[channelId];

        // _maxRelayFee is the _ackRelayFee from its corresponding BSC => GNFD sync package
        if (packageType == SYN_PACKAGE) {
            try IMiddleLayer(_handler).handleSynPackage(channelId, packageLoad) returns (bytes memory responsePayload) {
                if (responsePayload.length != 0) {
                    _sendPackage(
                        channelSendSequenceMap[channelId],
                        channelId,
                        encodePayload(ACK_PACKAGE, _ackRelayFee, 0, responsePayload)
                    );
                    channelSendSequenceMap[channelId] = channelSendSequenceMap[channelId] + 1;
                }
            } catch Error(string memory reason) {
                _sendPackage(
                    channelSendSequenceMap[channelId],
                    channelId,
                    encodePayload(FAIL_ACK_PACKAGE, _ackRelayFee, 0, packageLoad)
                );
                channelSendSequenceMap[channelId] = channelSendSequenceMap[channelId] + 1;
                emit UnexpectedRevertInPackageHandler(_handler, reason);
            } catch (bytes memory lowLevelData) {
                _sendPackage(
                    channelSendSequenceMap[channelId],
                    channelId,
                    encodePayload(FAIL_ACK_PACKAGE, _ackRelayFee, 0, packageLoad)
                );
                channelSendSequenceMap[channelId] = channelSendSequenceMap[channelId] + 1;
                emit UnexpectedFailureAssertionInPackageHandler(_handler, lowLevelData);
            }
            IRelayerHub(RELAYER_HUB).addReward(msg.sender, _maxRelayFee);
        } else {
            // _minAckRelayFee is the minimum relay fee for this callback in any case
            uint256 _minAckRelayFee = minAckRelayFee;
            uint256 _maxCallbackFee = _maxRelayFee > _minAckRelayFee ? _maxRelayFee - _minAckRelayFee : 0;
            uint256 _callbackGasLimit = _maxCallbackFee / callbackGasPrice;

            uint256 _refundFee;
            address _refundAddress;
            // TODO: The _refundAddress will be placed on the communication layer after
            if (packageType == ACK_PACKAGE) {
                try
                    IMiddleLayer(_handler).handleAckPackage(channelId, sequence, packageLoad, _callbackGasLimit)
                returns (uint256 remainingGas, address refundAddress) {
                    _refundFee = remainingGas * callbackGasPrice;
                    if (_refundFee > _maxCallbackFee) {
                        _refundFee = _maxCallbackFee;
                    }
                    _refundAddress = refundAddress;
                } catch Error(string memory reason) {
                    emit UnexpectedRevertInPackageHandler(_handler, reason);
                } catch (bytes memory lowLevelData) {
                    emit UnexpectedFailureAssertionInPackageHandler(_handler, lowLevelData);
                }
            } else if (packageType == FAIL_ACK_PACKAGE) {
                try
                    IMiddleLayer(_handler).handleFailAckPackage(channelId, sequence, packageLoad, _callbackGasLimit)
                returns (uint256 remainingGas, address refundAddress) {
                    _refundFee = remainingGas * callbackGasPrice;
                    if (_refundFee > _maxCallbackFee) {
                        _refundFee = _maxCallbackFee;
                    }
                    _refundAddress = refundAddress;
                } catch Error(string memory reason) {
                    emit UnexpectedRevertInPackageHandler(_handler, reason);
                } catch (bytes memory lowLevelData) {
                    emit UnexpectedFailureAssertionInPackageHandler(_handler, lowLevelData);
                }
            } else {
                // should not happen, still protect
                revert("Unknown Package Type");
            }

            if (_refundAddress != address(0)) {
                ITokenHub(TOKEN_HUB).refundCallbackGasFee(_refundAddress, _refundFee);
            } else {
                _refundFee = 0;
            }
            IRelayerHub(RELAYER_HUB).addReward(msg.sender, _maxRelayFee - _refundFee);
        }
    }

    function sendSynPackage(
        uint8 channelId,
        bytes calldata msgBytes,
        uint256 _relayFee,
        uint256 _ackRelayFee
    ) external onlyRegisteredContractChannel(channelId) {
        uint64 sendSequence = channelSendSequenceMap[channelId];
        _sendPackage(sendSequence, channelId, encodePayload(SYN_PACKAGE, _relayFee, _ackRelayFee, msgBytes));
        sendSequence++;
        channelSendSequenceMap[channelId] = sendSequence;
    }

    function suspend() external onlyRelayer onlyEOA whenNotSuspended {
        bool isExecutable = _approveProposal(SUSPEND_PROPOSAL, EMPTY_CONTENT_HASH);
        if (isExecutable) {
            isSuspended = true;
            emit Suspended(msg.sender);
        }
    }

    function reopen() external onlyRelayer onlyEOA whenSuspended {
        bool isExecutable = _approveProposal(REOPEN_PROPOSAL, EMPTY_CONTENT_HASH);
        if (isExecutable) {
            isSuspended = false;
            emit Reopened(msg.sender);
        }
    }

    function cancelTransfer(address attacker) external onlyRelayer onlyEOA {
        bytes32 _contentHash = keccak256(abi.encode(attacker));
        bool isExecutable = _approveProposal(CANCEL_TRANSFER_PROPOSAL, _contentHash);
        if (isExecutable) {
            ITokenHub(TOKEN_HUB).cancelTransferIn(attacker);
        }
    }

    function emergencyCancelTransfer(address attacker) external onlyEmergencyOperator {
        ITokenHub(TOKEN_HUB).cancelTransferIn(attacker);
    }

    function emergencySuspend() external onlyEmergencyOperator whenNotSuspended {
        isSuspended = true;
        emit Suspended(msg.sender);
    }

    function emergencyReopen() external onlyEmergencyOperator whenSuspended {
        isSuspended = false;
        emit Reopened(msg.sender);
    }

    function updateParam(string calldata key, bytes calldata value) external onlyGov whenNotSuspended {
        uint256 valueLength = value.length;
        if (_compareStrings(key, "relayFee")) {
            require(valueLength == 32, "invalid relayFee value length");
            uint256 newRelayFee = BytesToTypes.bytesToUint256(valueLength, value);
            require(newRelayFee <= 1 ether && newRelayFee > 0, "the newRelayFee should be in (0, 1 ether]");
            relayFee = newRelayFee;
        } else if (_compareStrings(key, "minAckRelayFee")) {
            require(valueLength == 32, "invalid minAckRelayFee value length");
            uint256 newMinAckRelayFee = BytesToTypes.bytesToUint256(valueLength, value);
            require(
                newMinAckRelayFee <= 1 ether && newMinAckRelayFee > 0,
                "the newMinAckRelayFee should be in (0, 1 ether]"
            );
            minAckRelayFee = newMinAckRelayFee;
        } else if (_compareStrings(key, "batchSizeForOracle")) {
            require(valueLength == 32, "invalid batchSizeForOracle value length");
            uint256 newBatchSizeForOracle = BytesToTypes.bytesToUint256(valueLength, value);
            require(
                newBatchSizeForOracle <= 10000 && newBatchSizeForOracle >= 10,
                "the newBatchSizeForOracle should be in [10, 10000]"
            );
            batchSizeForOracle = newBatchSizeForOracle;
        } else if (_compareStrings(key, "callbackGasPrice")) {
            require(valueLength == 32, "invalid callbackGasPrice value length");
            uint256 newCallbackGasPrice = BytesToTypes.bytesToUint256(valueLength, value);
            require(
                newCallbackGasPrice > 0 && newCallbackGasPrice < 1000 gwei,
                "the newCallbackGasPrice should be in (0, 1000 gwei)"
            );
            callbackGasPrice = newCallbackGasPrice;
        } else if (_compareStrings(key, "addOrUpdateChannel")) {
            require(
                valueLength == 21,
                "length of value for addOrUpdateChannel should be 21, channelId + handlerAddress"
            );
            bytes memory valueLocal = value;
            uint8 channelId;
            assembly {
                channelId := mload(add(valueLocal, 1))
            }

            address handlerContract;
            assembly {
                handlerContract := mload(add(valueLocal, 21))
            }

            require(_isContract(handlerContract), "address is not a contract");
            channelHandlerMap[channelId] = handlerContract;
            registeredContractChannelMap[handlerContract][channelId] = true;
            emit AddChannel(channelId, handlerContract);
        } else if (_compareStrings(key, "enableOrDisableChannel")) {
            bytes memory valueLocal = value;
            require(
                valueLocal.length == 2,
                "length of value for enableOrDisableChannel should be 2, channelId:isEnable"
            );

            uint8 channelId;
            assembly {
                channelId := mload(add(valueLocal, 1))
            }

            uint8 status;
            assembly {
                status := mload(add(valueLocal, 2))
            }

            bool isEnable = (status == 1);
            address handlerContract = channelHandlerMap[channelId];
            if (handlerContract != address(0x00)) {
                //channel existing
                registeredContractChannelMap[handlerContract][channelId] = isEnable;
                emit EnableOrDisableChannel(channelId, isEnable);
            }
        } else if (_compareStrings(key, "suspendQuorum")) {
            require(value.length == 2, "length of value for suspendQuorum should be 2");
            uint16 suspendQuorum = BytesToTypes.bytesToUint16(2, value);
            require(suspendQuorum > 0 && suspendQuorum < 100, "invalid suspend quorum");
            quorumMap[SUSPEND_PROPOSAL] = suspendQuorum;
        } else if (_compareStrings(key, "reopenQuorum")) {
            require(value.length == 2, "length of value for reopenQuorum should be 2");
            uint16 reopenQuorum = BytesToTypes.bytesToUint16(2, value);
            require(reopenQuorum > 0 && reopenQuorum < 100, "invalid reopen quorum");
            quorumMap[REOPEN_PROPOSAL] = reopenQuorum;
        } else if (_compareStrings(key, "cancelTransferQuorum")) {
            require(value.length == 2, "length of value for cancelTransferQuorum should be 2");
            uint16 cancelTransferQuorum = BytesToTypes.bytesToUint16(2, value);
            require(cancelTransferQuorum > 0 && cancelTransferQuorum < 100, "invalid cancel transfer quorum");
            quorumMap[CANCEL_TRANSFER_PROPOSAL] = cancelTransferQuorum;
        } else {
            revert("unknown param");
        }

        emit ParamChange(key, value);
    }

    /*----------------- internal function -----------------*/
    /*
    | SrcChainId | DestChainId | ChannelId | Sequence | PackageType | Timestamp | SynRelayerFee | AckRelayerFee(optional) | PackageLoad |
    | 2 bytes    |  2 bytes    |  1 byte   |  8 bytes |  1 byte     |  8 bytes  | 32 bytes      | 32 bytes / 0 bytes      |   len bytes |
    */

    function _checkPayload(
        bytes calldata payload
    )
        internal
        view
        returns (
            bool success,
            uint8 channelId,
            uint64 sequence,
            uint8 packageType,
            uint64 time,
            uint256 _relayFee,
            uint256 _ackRelayFee,
            bytes memory packageLoad
        )
    {
        if (payload.length < 54) {
            return (false, 0, 0, 0, 0, 0, 0, "");
        }

        bytes memory _payload = payload;
        uint256 ptr;
        {
            uint16 srcChainId;
            uint16 dstChainId;
            assembly {
                ptr := _payload

                srcChainId := mload(add(ptr, 2))
                dstChainId := mload(add(ptr, 4))
            }
            require(srcChainId == gnfdChainId, "invalid source chainId");
            require(dstChainId == chainId, "invalid destination chainId");
        }

        assembly {
            channelId := mload(add(ptr, 5))
            sequence := mload(add(ptr, 13))
            packageType := mload(add(ptr, 14))
            time := mload(add(ptr, 22))
            _relayFee := mload(add(ptr, 54))
        }

        if (packageType == SYN_PACKAGE) {
            if (payload.length < 86) {
                return (false, 0, 0, 0, 0, 0, 0, "");
            }

            assembly {
                _ackRelayFee := mload(add(ptr, 86))
            }
            packageLoad = payload[86:];
        } else {
            _ackRelayFee = 0;
            packageLoad = payload[54:];
        }
        success = true;

        require(_relayFee <= MAX_RELAY_FEE, "_relayFee too large");
        require(_ackRelayFee <= MAX_RELAY_FEE, "_ackRelayFee too large");
    }

    function _sendPackage(uint64 packageSequence, uint8 channelId, bytes memory payload) internal whenNotSuspended {
        if (block.number > previousTxHeight) {
            oracleSequence++;
            txCounter = 1;
            previousTxHeight = block.number;
        } else {
            txCounter++;
            if (txCounter > batchSizeForOracle) {
                oracleSequence++;
                txCounter = 1;
            }
        }
        emit CrossChainPackage(chainId, gnfdChainId, uint64(oracleSequence), packageSequence, channelId, payload);
    }

    function _approveProposal(bytes32 proposalTypeHash, bytes32 _contentHash) internal returns (bool isExecutable) {
        EmergencyProposal storage p = emergencyProposals[proposalTypeHash];

        // It is ok if there is an evil validator always cancel the previous vote,
        // the credible validator could use private transaction service to send a batch tx including 2 approve transactions
        if (block.timestamp >= p.expiredAt || p.contentHash != _contentHash) {
            // current proposal expired / not exist or not same with the new, create a new EmergencyProposal
            p.quorum = quorumMap[proposalTypeHash];
            p.expiredAt = uint128(block.timestamp + EMERGENCY_PROPOSAL_EXPIRE_PERIOD);
            p.contentHash = _contentHash;
            p.approvers = [msg.sender];

            emit ProposalSubmitted(proposalTypeHash, msg.sender, p.quorum, p.expiredAt, _contentHash);
        } else {
            // current proposal exists
            for (uint256 i = 0; i < p.approvers.length; ++i) {
                require(p.approvers[i] != msg.sender, "already approved");
            }
            p.approvers.push(msg.sender);
        }

        if (p.approvers.length >= p.quorum) {
            // 1. remove current proposal
            delete emergencyProposals[proposalTypeHash];

            // 2. exec this proposal
            return true;
        }

        return false;
    }

    function getRelayFees() external view returns (uint256 _relayFee, uint256 _minAckRelayFee) {
        return (relayFee, minAckRelayFee);
    }

    function versionInfo()
        external
        pure
        override
        returns (uint256 version, string memory name, string memory description)
    {
        return (200_001, "CrossChain", "init version");
    }
}
