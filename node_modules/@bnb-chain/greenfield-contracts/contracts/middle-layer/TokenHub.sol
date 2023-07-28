// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../Config.sol";
import "../lib/RLPEncode.sol";
import "../lib/RLPDecode.sol";
import "../interface/ICrossChain.sol";
import "../interface/IMiddleLayer.sol";

contract TokenHub is Config, ReentrancyGuardUpgradeable, IMiddleLayer {
    using RLPEncode for *;
    using RLPDecode for *;

    /*----------------- constants -----------------*/
    // transfer in channel
    uint8 public constant TRANSFER_IN_SUCCESS = 0;
    uint8 public constant TRANSFER_IN_FAILURE_INSUFFICIENT_BALANCE = 1;
    uint8 public constant TRANSFER_IN_FAILURE_NON_PAYABLE_RECIPIENT = 2;
    uint8 public constant TRANSFER_IN_FAILURE_UNKNOWN = 3;

    uint256 public constant MAX_GAS_FOR_TRANSFER_BNB = 5000;
    uint256 public constant REWARD_UPPER_LIMIT = 1e18;

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

    event TransferInSuccess(address refundAddress, uint256 amount);
    event TransferOutSuccess(address senderAddress, uint256 amount, uint256 relayFee, uint256 ackRelayFee);
    event RefundSuccess(address refundAddress, uint256 amount, uint32 status);
    event RefundFailure(address refundAddress, uint256 amount, uint32 status);
    event RewardTo(address to, uint256 amount);
    event ReceiveDeposit(address from, uint256 amount);
    event UnexpectedPackage(uint8 channelId, uint64 sequence, bytes msgBytes);
    event ParamChange(string key, bytes value);
    event SuccessRefundCallbackFee(address refundAddress, uint256 amount);
    event FailRefundCallbackFee(address refundAddress, uint256 amount);

    modifier onlyRelayerHub() {
        require(msg.sender == RELAYER_HUB, "only RelayerHub contract");
        _;
    }

    /*----------------- external function -----------------*/
    function initialize() public initializer {
        __ReentrancyGuard_init();
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
     * @param msgBytes The rlp encoded message bytes sent from BSC to GNFD
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
     * @param msgBytes The rlp encoded message bytes sent from GNFD
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
     * @param msgBytes The rlp encoded message bytes sent from GNFD
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

    function refundCallbackGasFee(address _refundAddress, uint256 _refundFee) external onlyCrossChain {
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
    function transferOut(address recipient, uint256 amount) external payable returns (bool) {
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

    function claimRelayFee(uint256 amount) external onlyRelayerHub returns (uint256) {
        uint256 actualAmount = amount < address(this).balance ? amount : address(this).balance;

        if (actualAmount > REWARD_UPPER_LIMIT) {
            return 0;
        }

        if (actualAmount > 0) {
            (bool success, ) = msg.sender.call{ gas: MAX_GAS_FOR_TRANSFER_BNB, value: actualAmount }("");
            require(success, "transfer bnb error");
            emit RewardTo(msg.sender, actualAmount);
        }

        return actualAmount;
    }

    /*----------------- internal function -----------------*/
    function _decodeTransferInSynPackage(
        bytes memory msgBytes
    ) internal pure returns (TransferInSynPackage memory, bool) {
        TransferInSynPackage memory transInSynPkg;

        RLPDecode.Iterator memory iter = msgBytes.toRLPItem().iterator();
        bool success = false;
        uint256 idx = 0;
        while (iter.hasNext()) {
            if (idx == 0) {
                transInSynPkg.amount = iter.next().toUint();
            } else if (idx == 1) {
                transInSynPkg.recipient = iter.next().toAddress();
            } else if (idx == 2) {
                transInSynPkg.refundAddr = iter.next().toAddress();
                success = true;
            } else {
                break;
            }
            idx++;
        }
        return (transInSynPkg, success);
    }

    function _encodeTransferInRefundPackage(
        TransferInRefundPackage memory transInAckPkg
    ) internal pure returns (bytes memory) {
        bytes[] memory elements = new bytes[](3);
        elements[0] = transInAckPkg.refundAmount.encodeUint();
        elements[1] = transInAckPkg.refundAddr.encodeAddress();
        elements[2] = uint256(transInAckPkg.status).encodeUint();
        return elements.encodeList();
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

    function _doTransferIn(TransferInSynPackage memory transInSynPkg) internal returns (uint32) {
        if (address(this).balance < transInSynPkg.amount) {
            return TRANSFER_IN_FAILURE_INSUFFICIENT_BALANCE;
        }
        (bool success, ) = transInSynPkg.recipient.call{ gas: MAX_GAS_FOR_TRANSFER_BNB, value: transInSynPkg.amount }(
            ""
        );
        if (!success) {
            return TRANSFER_IN_FAILURE_NON_PAYABLE_RECIPIENT;
        }
        emit TransferInSuccess(transInSynPkg.recipient, transInSynPkg.amount);
        return TRANSFER_IN_SUCCESS;
    }

    function _decodeTransferOutAckPackage(
        bytes memory msgBytes
    ) internal pure returns (TransferOutAckPackage memory, bool) {
        TransferOutAckPackage memory transOutAckPkg;

        RLPDecode.Iterator memory iter = msgBytes.toRLPItem().iterator();
        bool success = false;
        uint256 idx = 0;
        while (iter.hasNext()) {
            if (idx == 0) {
                transOutAckPkg.refundAmount = iter.next().toUint();
            } else if (idx == 1) {
                transOutAckPkg.refundAddr = ((iter.next().toAddress()));
            } else if (idx == 2) {
                transOutAckPkg.status = uint32(iter.next().toUint());
                success = true;
            } else {
                break;
            }
            idx++;
        }
        return (transOutAckPkg, success);
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
        TransferOutSynPackage memory transOutSynPkg;

        RLPDecode.Iterator memory iter = msgBytes.toRLPItem().iterator();
        bool success = false;
        uint256 idx = 0;
        while (iter.hasNext()) {
            if (idx == 0) {
                transOutSynPkg.amount = iter.next().toUint();
            } else if (idx == 1) {
                transOutSynPkg.recipient = ((iter.next().toAddress()));
            } else if (idx == 2) {
                transOutSynPkg.refundAddr = iter.next().toAddress();
                success = true;
            } else {
                break;
            }
            idx++;
        }
        return (transOutSynPkg, success);
    }

    function _handleTransferOutFailAckPackage(bytes memory msgBytes) internal {
        (TransferOutSynPackage memory transOutSynPkg, bool decodeSuccess) = _decodeTransferOutSynPackage(msgBytes);
        require(decodeSuccess, "unrecognized transferOut syn package");
        TransferOutAckPackage memory transOutAckPkg;
        transOutAckPkg.refundAmount = transOutSynPkg.amount;
        transOutAckPkg.refundAddr = transOutSynPkg.refundAddr;
        transOutAckPkg.status = TRANSFER_IN_FAILURE_UNKNOWN;
        _doRefund(transOutAckPkg);
    }

    function _encodeTransferOutSynPackage(
        TransferOutSynPackage memory transOutSynPkg
    ) internal pure returns (bytes memory) {
        bytes[] memory elements = new bytes[](3);
        elements[0] = transOutSynPkg.amount.encodeUint();
        elements[1] = transOutSynPkg.recipient.encodeAddress();
        elements[2] = transOutSynPkg.refundAddr.encodeAddress();
        return elements.encodeList();
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
