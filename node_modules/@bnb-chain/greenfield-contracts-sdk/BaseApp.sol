// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./storage/CmnStorage.sol";
import "./interface/ICrossChain.sol";

/**
 * @dev Contract module that defines common constants/variables/functions.
 * This module is used through inheritance.
 */
abstract contract BaseApp is Initializable {
    /*----------------- constants -----------------*/
    // status of cross-chain package
    // every package from BSC to greenfield will have a response with a status
    // 0: success
    // 1: failed
    // 2: unexpected, which means unexpected error happened in the underlying cross-chain process
    uint32 public constant STATUS_SUCCESS = 0;
    uint32 public constant STATUS_FAILED = 1;
    uint32 public constant STATUS_UNEXPECTED = 2;

    // operation type
    // for a resource, there are three basic operation types
    // 1: mirror, which is not available for external contracts
    // 2: create, which means create a new resource
    // 3: delete, which means delete an existing resource
    uint8 public constant TYPE_CREATE = 2;
    uint8 public constant TYPE_DELETE = 3;

    // error code
    // short error code for each error
    string public constant ERROR_INVALID_CALLER = "0";
    string public constant ERROR_INVALID_RESOURCE = "1";
    string public constant ERROR_INVALID_OPERATION = "2";
    string public constant ERROR_INSUFFICIENT_VALUE = "3";

    /*----------------- storage -----------------*/
    // system contract
    address public crossChain;

    // callback config
    // necessary config for callback
    // callbackGasLimit: the gas limit for callback. Will be charged in advance
    // when the transaction is initiated, so it must be attached to the msg.value.
    // failureHandleStrategy: the strategy to handle the failure of callback.
    uint256 public callbackGasLimit;
    CmnStorage.FailureHandleStrategy public failureHandleStrategy;

    /*----------------- initializer -----------------*/
    /**
     * @dev Sets the values for {crossChain}, {callbackGasLimit}, {refundAddress} and {failureHandleStrategy}.
     */
    function __base_app_init(
        address _crossChain,
        uint256 _callbackGasLimit,
        uint8 _failureHandlerStrategy
    ) internal onlyInitializing {
        __base_app_init_unchained(_crossChain, _callbackGasLimit, _failureHandlerStrategy);
    }

    function __base_app_init_unchained(
        address _crossChain,
        uint256 _callbackGasLimit,
        uint8 _failureHandlerStrategy
    ) internal onlyInitializing {
        crossChain = _crossChain;

        callbackGasLimit = _callbackGasLimit;
        failureHandleStrategy = CmnStorage.FailureHandleStrategy(_failureHandlerStrategy);
    }

    /*----------------- external functions -----------------*/
    /**
     * @dev Callback hook for greenfield system contract.
     * This function will be triggered when a cross-chain operation is completed on greenfield side
     * and return a package to bsc.
     * If the developers don’t need callback, this function can be undefined.
     */
    function greenfieldCall(
        uint32 status,
        uint8 resourceType,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external virtual {}

    /**
     * @dev Retry failed package according to the `resourceType`.
     */
    function retryPackage(uint8 resourceType) external virtual {}

    /**
     * @dev Skip failed package according to the `resourceType`.
     */
    function skipPackage(uint8 resourceType) external virtual {}

    /*----------------- internal functions -----------------*/
    /**
     * @dev Set `callbackGasLimit`.
     */
    function _setCallbackGasLimit(uint256 _callbackGasLimit) internal virtual {
        callbackGasLimit = _callbackGasLimit;
    }

    /**
     * @dev Set `failureHandleStrategy`.
     */
    function _setFailureHandleStrategy(uint8 _failureHandleStrategy) internal virtual {
        failureHandleStrategy = CmnStorage.FailureHandleStrategy(_failureHandleStrategy);
    }

    /**
     * @dev Get the total fee for a cross-chain transaction.
     */
    function _getTotalFee() internal returns (uint256) {
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(crossChain).getRelayFees();
        uint256 gasPrice = ICrossChain(crossChain).callbackGasPrice();
        return relayFee + minAckRelayFee + callbackGasLimit * gasPrice;
    }
}
