// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../Config.sol";
import "../lib/BytesToTypes.sol";
import "../interface/ICrossChain.sol";
import "../interface/IMiddleLayer.sol";
import "../interface/ITokenHub.sol";

contract TokenHub is Config, ReentrancyGuardUpgradeable, IMiddleLayer, ITokenHub {
    /*----------------- constants -----------------*/
    // transfer in channel
    uint8 public constant TRANSFER_IN_SUCCESS = 0;
    uint8 public constant TRANSFER_IN_FAILURE_INSUFFICIENT_BALANCE = 1;
    uint8 public constant TRANSFER_IN_FAILURE_NON_PAYABLE_RECIPIENT = 2;
    uint8 public constant TRANSFER_IN_FAILURE_UNKNOWN = 3;

    uint256 public constant MAX_GAS_FOR_TRANSFER_BNB = 5000;
    uint256 public constant REWARD_UPPER_LIMIT = 1e18;

    /*----------------- storage layer -----------------*/
    uint256 public largeTransferLimit;
    // the lock period for large transfer
    uint256 public lockPeriod;
    // token address => recipient address => lockedAmount + unlockAt, address(0) means BNB
    mapping(address => LockInfo) public lockInfoMap;

    /*----------------- struct / event / modifier -----------------*/
    struct TransferOutSynPackage {
        uint256 amount;
        address recipient;
        address refundAddr;
    }

    // GNFD to BSC
    struct TransferOutAckPackage {
        uint256 refundAmount;
        address refundAddr;
        uint32 status;
    }

    // GNFD to BSC
    struct TransferInSynPackage {
        uint256 amount;
        address recipient;
        address refundAddr;
    }

    // BSC to GNFD
    struct TransferInRefundPackage {
        uint256 refundAmount;
        address refundAddr;
        uint32 status;
    }

    struct LockInfo {
        uint256 amount;
        uint256 unlockAt;
    }

    event TransferInSuccess(address recipient, uint256 amount);
    event TransferOutSuccess(address senderAddress, uint256 amount, uint256 relayFee, uint256 ackRelayFee);
    event RefundSuccess(address refundAddress, uint256 amount, uint32 status);
    event RefundFailure(address refundAddress, uint256 amount, uint32 status);
    event TransferTo(address to, uint256 amount);
    event ReceiveDeposit(address from, uint256 amount);
    event UnexpectedPackage(uint8 channelId, uint64 sequence, bytes msgBytes);
    event ParamChange(string key, bytes value);
    event SuccessRefundCallbackFee(address refundAddress, uint256 amount);
    event FailRefundCallbackFee(address refundAddress, uint256 amount);
    event LargeTransferLocked(address indexed recipient, uint256 amount, uint256 unlockAt);
    event WithdrawUnlockedToken(address indexed recipient, uint256 amount);
    event CancelTransfer(address indexed attacker, uint256 amount);
    event LargeTransferLimitSet(address indexed owner, uint256 largeTransferLimit);

    modifier onlyRelayerHub() {
        require(msg.sender == RELAYER_HUB, "only RelayerHub contract");
        _;
    }

    /*----------------- external function -----------------*/
    function initialize() public initializer {
        __ReentrancyGuard_init();

        largeTransferLimit = 1000 ether;
        lockPeriod = 12 hours;
    }

    receive() external payable {
        if (msg.value > 0) {
            emit ReceiveDeposit(msg.sender, msg.value);
        }
    }

    /**
     * @dev handle sync cross-chain package from BSC to GNFD
     *
     * @param channelId The channel for cross-chain communication
     * @param msgBytes The encoded message bytes sent from BSC to GNFD
     */
    function handleSynPackage(uint8 channelId, bytes calldata msgBytes) external onlyCrossChain returns (bytes memory) {
        if (channelId == TRANSFER_IN_CHANNEL_ID) {
            return _handleTransferInSynPackage(msgBytes);
        } else {
            // should not happen
            require(false, "unrecognized syn package");
            return new bytes(0);
        }
    }

    /**
     * @dev handle ack cross-chain package from GNFD，it means cross-chain transfer successfully to GNFD
     * and will refund the remaining token caused by different decimals between BSC and GNFD.
     *
     * @param channelId The channel for cross-chain communication
     * @param msgBytes The encoded message bytes sent from GNFD
     */
    function handleAckPackage(
        uint8 channelId,
        uint64 sequence,
        bytes calldata msgBytes,
        uint256
    ) external onlyCrossChain returns (uint256 remainingGas, address refundAddress) {
        if (channelId == TRANSFER_OUT_CHANNEL_ID) {
            _handleTransferOutAckPackage(msgBytes);
        } else {
            emit UnexpectedPackage(channelId, sequence, msgBytes);
        }

        return (0, address(0));
    }

    /**
     * @dev handle failed ack cross-chain package from GNFD, it means failed to cross-chain transfer to GNFD and will refund the token.
     *
     * @param channelId The channel for cross-chain communication
     * @param msgBytes The encoded message bytes sent from GNFD
     */
    function handleFailAckPackage(
        uint8 channelId,
        uint64 sequence,
        bytes calldata msgBytes,
        uint256
    ) external onlyCrossChain returns (uint256 remainingGas, address refundAddress) {
        if (channelId == TRANSFER_OUT_CHANNEL_ID) {
            _handleTransferOutFailAckPackage(msgBytes);
        } else {
            emit UnexpectedPackage(channelId, sequence, msgBytes);
        }

        return (0, address(0));
    }

    function refundCallbackGasFee(address _refundAddress, uint256 _refundFee) external override onlyCrossChain {
        (bool success, ) = _refundAddress.call{ gas: MAX_GAS_FOR_TRANSFER_BNB, value: _refundFee }("");
        if (success) {
            emit SuccessRefundCallbackFee(_refundAddress, _refundFee);
        } else {
            emit FailRefundCallbackFee(_refundAddress, _refundFee);
        }
    }

    /**
     * @dev request a cross-chain transfer from BSC to GNFD
     *
     * @param recipient The destination address of the cross-chain transfer on GNFD.
     * @param amount The amount to transfer
     */
    function transferOut(address recipient, uint256 amount) external payable override returns (bool) {
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(CROSS_CHAIN).getRelayFees();

        require(
            msg.value >= amount + relayFee + minAckRelayFee,
            "received BNB amount should be no less than the sum of transferOut BNB amount and minimum relayFee"
        );
        uint256 _ackRelayFee = msg.value - amount - relayFee;

        TransferOutSynPackage memory transOutSynPkg = TransferOutSynPackage({
            amount: amount,
            recipient: recipient,
            refundAddr: msg.sender
        });

        address _crosschain = CROSS_CHAIN;
        ICrossChain(_crosschain).sendSynPackage(
            TRANSFER_OUT_CHANNEL_ID,
            _encodeTransferOutSynPackage(transOutSynPkg),
            relayFee,
            _ackRelayFee
        );
        emit TransferOutSuccess(msg.sender, amount, relayFee, _ackRelayFee);
        return true;
    }

    function claimRelayFee(uint256 amount) external override onlyRelayerHub returns (uint256) {
        uint256 actualAmount = amount < address(this).balance ? amount : address(this).balance;

        // should not happen, still protect
        if (actualAmount > REWARD_UPPER_LIMIT) {
            return 0;
        }

        if (actualAmount > 0) {
            (bool success, ) = msg.sender.call{ gas: MAX_GAS_FOR_TRANSFER_BNB, value: actualAmount }("");
            require(success, "transfer bnb error");
            emit TransferTo(msg.sender, actualAmount);
        }

        return actualAmount;
    }

    function withdrawUnlockedToken(address recipient) external nonReentrant {
        LockInfo storage lockInfo = lockInfoMap[recipient];
        require(lockInfo.amount > 0, "no locked amount");
        require(block.timestamp >= lockInfo.unlockAt, "still on locking period");

        uint256 _amount = lockInfo.amount;
        lockInfo.amount = 0;

        (bool _success, ) = recipient.call{ gas: MAX_GAS_FOR_TRANSFER_BNB, value: _amount }("");
        require(_success, "withdraw unlocked token failed");

        emit WithdrawUnlockedToken(recipient, _amount);
    }

    function cancelTransferIn(address attacker) external override onlyCrossChain {
        LockInfo storage lockInfo = lockInfoMap[attacker];
        require(lockInfo.amount > 0, "no locked amount");

        uint256 _amount = lockInfo.amount;
        lockInfo.amount = 0;

        emit CancelTransfer(attacker, _amount);
    }

    function updateParam(string calldata key, bytes calldata value) external onlyGov {
        uint256 valueLength = value.length;
        if (_compareStrings(key, "largeTransferLimit")) {
            require(valueLength == 32, "invalid largeTransferLimit value length");
            uint256 newLargeTransferLimit = BytesToTypes.bytesToUint256(valueLength, value);
            require(newLargeTransferLimit >= 100 ether, "bnb largeTransferLimit too small");
            largeTransferLimit = newLargeTransferLimit;
        } else if (_compareStrings(key, "lockPeriod")) {
            require(valueLength == 32, "invalid lockPeriod value length");
            uint256 newLockPeriod = BytesToTypes.bytesToUint256(valueLength, value);
            require(newLockPeriod <= 1 weeks, "lock period too long");
            lockPeriod = newLockPeriod;
        } else {
            revert("unknown param");
        }
        emit ParamChange(key, value);
    }

    /*----------------- internal function -----------------*/
    function _decodeTransferInSynPackage(
        bytes memory msgBytes
    ) internal pure returns (TransferInSynPackage memory, bool) {
        TransferInSynPackage memory transInSynPkg = abi.decode(msgBytes, (TransferInSynPackage));
        return (transInSynPkg, true);
    }

    function _encodeTransferInRefundPackage(
        TransferInRefundPackage memory transInAckPkg
    ) internal pure returns (bytes memory) {
        return abi.encode(transInAckPkg);
    }

    function _handleTransferInSynPackage(bytes memory msgBytes) internal returns (bytes memory) {
        (TransferInSynPackage memory transInSynPkg, bool success) = _decodeTransferInSynPackage(msgBytes);
        require(success, "unrecognized transferIn package");
        uint32 resCode = _doTransferIn(transInSynPkg);
        if (resCode != TRANSFER_IN_SUCCESS) {
            TransferInRefundPackage memory transInAckPkg = TransferInRefundPackage({
                refundAmount: transInSynPkg.amount,
                refundAddr: transInSynPkg.refundAddr,
                status: resCode
            });
            return _encodeTransferInRefundPackage(transInAckPkg);
        } else {
            return new bytes(0);
        }
    }

    function _checkAndLockTransferIn(TransferInSynPackage memory transInSynPkg) internal returns (bool isLocked) {
        // check if it is over large transfer limit
        if (transInSynPkg.amount < largeTransferLimit) {
            return false;
        }

        // it is over the large transfer limit
        // add time lock to recipient
        LockInfo storage lockInfo = lockInfoMap[transInSynPkg.recipient];
        lockInfo.amount = lockInfo.amount + transInSynPkg.amount;
        lockInfo.unlockAt = block.timestamp + lockPeriod;

        emit LargeTransferLocked(transInSynPkg.recipient, transInSynPkg.amount, lockInfo.unlockAt);
        return true;
    }

    function _doTransferIn(TransferInSynPackage memory transInSynPkg) internal returns (uint32) {
        if (address(this).balance < transInSynPkg.amount) {
            return TRANSFER_IN_FAILURE_INSUFFICIENT_BALANCE;
        }

        if (!_checkAndLockTransferIn(transInSynPkg)) {
            (bool success, ) = transInSynPkg.recipient.call{
                gas: MAX_GAS_FOR_TRANSFER_BNB,
                value: transInSynPkg.amount
            }("");
            if (!success) {
                return TRANSFER_IN_FAILURE_NON_PAYABLE_RECIPIENT;
            }
        }

        emit TransferInSuccess(transInSynPkg.recipient, transInSynPkg.amount);
        return TRANSFER_IN_SUCCESS;
    }

    function _decodeTransferOutAckPackage(
        bytes memory msgBytes
    ) internal pure returns (TransferOutAckPackage memory, bool) {
        TransferOutAckPackage memory transOutAckPkg = abi.decode(msgBytes, (TransferOutAckPackage));
        return (transOutAckPkg, true);
    }

    function _handleTransferOutAckPackage(bytes memory msgBytes) internal {
        (TransferOutAckPackage memory transOutAckPkg, bool decodeSuccess) = _decodeTransferOutAckPackage(msgBytes);
        require(decodeSuccess, "unrecognized transferOut ack package");
        _doRefund(transOutAckPkg);
    }

    function _doRefund(TransferOutAckPackage memory transOutAckPkg) internal {
        (bool success, ) = transOutAckPkg.refundAddr.call{
            gas: MAX_GAS_FOR_TRANSFER_BNB,
            value: transOutAckPkg.refundAmount
        }("");
        if (!success) {
            emit RefundFailure(transOutAckPkg.refundAddr, transOutAckPkg.refundAmount, transOutAckPkg.status);
        } else {
            emit RefundSuccess(transOutAckPkg.refundAddr, transOutAckPkg.refundAmount, transOutAckPkg.status);
        }
    }

    function _decodeTransferOutSynPackage(
        bytes memory msgBytes
    ) internal pure returns (TransferOutSynPackage memory, bool) {
        TransferOutSynPackage memory transOutSynPkg = abi.decode(msgBytes, (TransferOutSynPackage));
        return (transOutSynPkg, true);
    }

    function _handleTransferOutFailAckPackage(bytes memory msgBytes) internal {
        TransferOutSynPackage memory transOutSynPkg = abi.decode(msgBytes, (TransferOutSynPackage));
        TransferOutAckPackage memory transOutAckPkg;
        transOutAckPkg.refundAmount = transOutSynPkg.amount;
        transOutAckPkg.refundAddr = transOutSynPkg.refundAddr;
        transOutAckPkg.status = TRANSFER_IN_FAILURE_UNKNOWN;
        _doRefund(transOutAckPkg);
    }

    function _encodeTransferOutSynPackage(
        TransferOutSynPackage memory transOutSynPkg
    ) internal pure returns (bytes memory) {
        return abi.encode(transOutSynPkg);
    }

    function versionInfo()
        external
        pure
        override
        returns (uint256 version, string memory name, string memory description)
    {
        return (300_001, "TokenHub", "init version");
    }
}
