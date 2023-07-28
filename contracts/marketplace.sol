// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@bnb-chain/greenfield-contracts/contracts/lib/RLPDecode.sol";
import "@bnb-chain/greenfield-contracts/contracts/lib/RLPEncode.sol";
import "@bnb-chain/greenfield-contracts-sdk/GroupApp.sol";
import "@bnb-chain/greenfield-contracts-sdk/interface/IERC721NonTransferable.sol";
import "@bnb-chain/greenfield-contracts-sdk/interface/IERC1155NonTransferable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableMapUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/DoubleEndedQueueUpgradeable.sol";

contract Marketplace is ReentrancyGuard, AccessControl, GroupApp, GroupStorage {
    using RLPDecode for *;
    using RLPEncode for *;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;

    /*----------------- constants -----------------*/
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // greenfield system contracts
    address public constant CROSS_CHAIN = 0x57b8A375193b2e9c6481f167BaECF1feEf9F7d4B;
    address public constant GROUP_HUB = 0x0Bf7D3Ed3F777D7fB8D65Fb21ba4FBD9F584B579;
    address public constant GROUP_TOKEN = 0x089AFF7964E435eB2C7b296B371078B18E2C9A35;
    address public constant MEMBER_TOKEN = 0x80Dd11998159cbea4BF79650fCc5Da72Ffb51EFc;

    /*----------------- storage -----------------*/
    // group ID => item price
    mapping(uint256 => uint256) public prices;
    // group ID => total sales volume
    mapping(uint256 => uint256) public salesVolume;
    // group ID => total sales revenue
    mapping(uint256 => uint256) public salesRevenue;
    // group ID => listed date
    mapping(uint256 => uint256) public listedDate;

    // address => unclaimed amount
    mapping(address => uint256) private _unclaimedFunds;

    // all listed group _ids, ordered by listed time
    EnumerableSetUpgradeable.UintSet private _listedGroups;

    // sales volume ranking list, ordered by sales volume(desc)
    uint256[] private _salesVolumeRanking;
    // group ID corresponding to the sales volume ranking list, ordered by sales volume(desc)
    uint256[] private _salesVolumeRankingId;

    // sales revenue ranking list, ordered by sales revenue(desc)
    uint256[] private _salesRevenueRanking;
    // group ID corresponding to the sales revenue ranking list, ordered by sales revenue(desc)
    uint256[] private _salesRevenueRankingId;

    // user address => user listed group IDs, ordered by listed time
    mapping(address => EnumerableSetUpgradeable.UintSet) private _userListedGroups;
    // user address => user purchased group IDs, ordered by purchased time
    mapping(address => EnumerableSetUpgradeable.UintSet) private _userPurchasedGroups;

    address public fundWallet;

    uint256 public transferGasLimit; // 2300 for now
    uint256 public feeRate; // 10000 = 100%

    /*----------------- event/modifier -----------------*/
    event List(address indexed owner, uint256 indexed groupId, uint256 price);
    event Delist(address indexed owner, uint256 indexed groupId);
    event Buy(address indexed buyer, uint256 indexed groupId);
    event BuyFailed(address indexed buyer, uint256 indexed groupId);

    modifier onlyGroupOwner(uint256 groupId) {
        require(msg.sender == IERC721NonTransferable(GROUP_TOKEN).ownerOf(groupId), "MarketPlace: only group owner");
        _;
    }

    function initialize(
        address _initAdmin,
        address _fundWallet,
        uint256 _feeRate,
        uint256 _callbackGasLimit,
        uint8 _failureHandleStrategy
    ) public initializer {
        require(_initAdmin != address(0), "MarketPlace: invalid admin address");
        _grantRole(DEFAULT_ADMIN_ROLE, _initAdmin);

        transferGasLimit = 2300;
        fundWallet = _fundWallet;
        feeRate = _feeRate;

        __base_app_init_unchained(CROSS_CHAIN, _callbackGasLimit, _failureHandleStrategy);
        __group_app_init_unchained(GROUP_HUB);

        // init sales ranking
        _salesVolumeRanking = new uint256[](10);
        _salesVolumeRankingId = new uint256[](10);
        _salesRevenueRanking = new uint256[](10);
        _salesRevenueRankingId = new uint256[](10);
    }

    /*----------------- external functions -----------------*/
    function greenfieldCall(
        uint32 status,
        uint8 resourceType,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external override(GroupApp) {
        require(msg.sender == GROUP_HUB, "MarketPlace: invalid caller");

        if (resourceType == RESOURCE_GROUP) {
            _groupGreenfieldCall(status, operationType, resourceId, callbackData);
        } else {
            revert("MarketPlace: invalid resource type");
        }
    }

    function list(uint256 groupId, uint256 price) external onlyGroupOwner(groupId) {
        // the owner need to approve the marketplace contract to update the group
        require(IGroupHub(GROUP_HUB).hasRole(ROLE_UPDATE, msg.sender, address(this)), "Marketplace: no grant");
        require(prices[groupId] == 0, "Marketplace: already listed");
        require(price > 0, "Marketplace: invalid price");

        prices[groupId] = price;
        listedDate[groupId] = block.timestamp;
        _listedGroups.add(groupId);
        _userListedGroups[msg.sender].add(groupId);

        emit List(msg.sender, groupId, price);
    }

    function setPrice(uint256 groupId, uint256 newPrice) external onlyGroupOwner(groupId) {
        require(prices[groupId] > 0, "MarketPlace: not listed");
        require(newPrice > 0, "MarketPlace: invalid price");

        prices[groupId] = newPrice;
    }

    function delist(uint256 groupId) external onlyGroupOwner(groupId) {
        require(prices[groupId] > 0, "MarketPlace: not listed");

        delete prices[groupId];
        delete listedDate[groupId];
        delete salesVolume[groupId];
        delete salesRevenue[groupId];
        _listedGroups.remove(groupId);
        _userListedGroups[msg.sender].remove(groupId);

        for (uint256 i; i < _salesVolumeRankingId.length; ++i) {
            if (_salesVolumeRankingId[i] == groupId) {
                for (uint256 j = i; j < _salesVolumeRankingId.length - 1; ++j) {
                    _salesVolumeRankingId[j] = _salesVolumeRankingId[j + 1];
                    _salesVolumeRanking[j] = _salesVolumeRanking[j + 1];
                }
                _salesVolumeRankingId[_salesVolumeRankingId.length - 1] = 0;
                _salesVolumeRanking[_salesVolumeRanking.length - 1] = 0;
                break;
            }
        }

        for (uint256 i; i < _salesRevenueRankingId.length; ++i) {
            if (_salesRevenueRankingId[i] == groupId) {
                for (uint256 j = i; j < _salesRevenueRankingId.length - 1; ++j) {
                    _salesRevenueRankingId[j] = _salesRevenueRankingId[j + 1];
                    _salesRevenueRanking[j] = _salesRevenueRanking[j + 1];
                }
                _salesRevenueRankingId[_salesRevenueRankingId.length - 1] = 0;
                _salesRevenueRanking[_salesRevenueRankingId.length - 1] = 0;
                break;
            }
        }

        emit Delist(msg.sender, groupId);
    }

    function buy(uint256 groupId, address refundAddress) external payable {
        uint256 price = prices[groupId];
        require(price > 0, "MarketPlace: not listed");
        require(!_userPurchasedGroups[msg.sender].contains(groupId), "MarketPlace: already purchased");
        require(msg.value >= prices[groupId] + _getTotalFee(), "MarketPlace: insufficient fund");

        _buy(groupId, refundAddress, msg.value - price);
    }

    function buyBatch(uint256[] calldata groupIds, address refundAddress) external payable {
        uint256 receivedValue = msg.value;
        uint256 relayFee = _getTotalFee();
        uint256 amount;
        for (uint256 i; i < groupIds.length; ++i) {
            require(prices[groupIds[i]] > 0, "MarketPlace: not listed");
            require(!_userPurchasedGroups[msg.sender].contains(groupIds[i]), "MarketPlace: already purchased");

            amount = prices[groupIds[i]] + relayFee;
            require(receivedValue >= amount, "MarketPlace: insufficient fund");
            receivedValue -= amount;

            _buy(groupIds[i], refundAddress, relayFee);
        }
        if (receivedValue > 0) {
            (bool success,) = payable(refundAddress).call{gas: transferGasLimit, value: receivedValue}("");
            if (!success) {
                _unclaimedFunds[refundAddress] += receivedValue;
            }
        }
    }

    function claim() external nonReentrant {
        uint256 amount = _unclaimedFunds[msg.sender];
        require(amount > 0, "MarketPlace: no unclaimed funds");
        _unclaimedFunds[msg.sender] = 0;
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "MarketPlace: claim failed");
    }

    /*----------------- view functions -----------------*/
    function getMinRelayFee() external returns (uint256 amount) {
        amount = _getTotalFee();
    }

    function getUnclaimedAmount() external view returns (uint256 amount) {
        amount = _unclaimedFunds[msg.sender];
    }

    function getSalesVolumeRanking()
        external
        view
        returns (uint256[] memory _ids, uint256[] memory _volumes, uint256[] memory _dates)
    {
        _ids = _salesVolumeRankingId;
        _volumes = _salesVolumeRanking;

        _dates = new uint256[](_ids.length);
        for (uint256 i; i < _ids.length; ++i) {
            _dates[i] = listedDate[_ids[i]];
        }
    }

    function getSalesRevenueRanking()
        external
        view
        returns (uint256[] memory _ids, uint256[] memory _revenues, uint256[] memory _dates)
    {
        _ids = _salesRevenueRankingId;
        _revenues = _salesRevenueRanking;

        _dates = new uint256[](_ids.length);
        for (uint256 i; i < _ids.length; ++i) {
            _dates[i] = listedDate[_ids[i]];
        }
    }

    function getListed(
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory _ids, uint256[] memory _dates, uint256 _totalLength) {
        _totalLength = _listedGroups.length();
        if (offset >= _totalLength) {
            return (_ids, _dates, _totalLength);
        }

        uint256 count = _totalLength - offset;
        if (count > limit) {
            count = limit;
        }
        _ids = new uint256[](count);
        _dates = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            _ids[i] = _listedGroups.at(_totalLength - offset - i - 1); // reverse order
            _dates[i] = listedDate[_ids[i]];
        }
    }

    function getSalesRevenue(
        uint256 offset,
        uint256 limit
    )
        external
        view
        returns (uint256[] memory _ids, uint256[] memory _revenues, uint256[] memory _dates, uint256 _totalLength)
    {
        _totalLength = _listedGroups.length();
        if (offset >= _totalLength) {
            return (_ids, _revenues, _dates, _totalLength);
        }

        uint256 count = _totalLength - offset;
        if (count > limit) {
            count = limit;
        }
        _ids = new uint256[](count);
        _revenues = new uint256[](count);
        _dates = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            _ids[i] = _listedGroups.at(offset + i);
            _revenues[i] = salesRevenue[_ids[i]];
            _dates[i] = listedDate[_ids[i]];
        }
    }

    function getSalesVolume(
        uint256 offset,
        uint256 limit
    )
        external
        view
        returns (uint256[] memory _ids, uint256[] memory _volumes, uint256[] memory _dates, uint256 _totalLength)
    {
        _totalLength = _listedGroups.length();
        if (offset >= _totalLength) {
            return (_ids, _volumes, _dates, _totalLength);
        }

        uint256 count = _totalLength - offset;
        if (count > limit) {
            count = limit;
        }
        _ids = new uint256[](count);
        _volumes = new uint256[](count);
        _dates = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            _ids[i] = _listedGroups.at(offset + i);
            _volumes[i] = salesVolume[_ids[i]];
            _dates[i] = listedDate[_ids[i]];
        }
    }

    function getUserPurchased(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory _ids, uint256[] memory _dates, uint256 _totalLength) {
        _totalLength = _userPurchasedGroups[user].length();
        if (offset >= _totalLength) {
            return (_ids, _dates, _totalLength);
        }

        uint256 count = _totalLength - offset;
        if (count > limit) {
            count = limit;
        }
        _ids = new uint256[](count);
        _dates = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            _ids[i] = _userPurchasedGroups[user].at(offset + i);
            _dates[i] = listedDate[_ids[i]];
        }
    }

    function getUserListed(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory _ids, uint256[] memory _dates, uint256 _totalLength) {
        _totalLength = _userListedGroups[user].length();
        if (offset >= _totalLength) {
            return (_ids, _dates, _totalLength);
        }

        uint256 count = _totalLength - offset;
        if (count > limit) {
            count = limit;
        }
        _ids = new uint256[](count);
        _dates = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            _ids[i] = _userListedGroups[user].at(offset + i);
            _dates[i] = listedDate[_ids[i]];
        }
    }

    /*----------------- admin functions -----------------*/
    function addOperator(address newOperator) external {
        grantRole(OPERATOR_ROLE, newOperator);
    }

    function removeOperator(address operator) external {
        revokeRole(OPERATOR_ROLE, operator);
    }

    function setFundWallet(address _fundWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        fundWallet = _fundWallet;
    }

    function retryPackage(uint8) external override onlyRole(OPERATOR_ROLE) {
        _retryGroupPackage();
    }

    function skipPackage(uint8) external override onlyRole(OPERATOR_ROLE) {
        _skipGroupPackage();
    }

    function setFeeRate(uint256 _feeRate) external onlyRole(OPERATOR_ROLE) {
        require(_feeRate < 10_000, "MarketPlace: invalid feeRate");
        feeRate = _feeRate;
    }

    function setCallbackGasLimit(uint256 _callbackGasLimit) external onlyRole(OPERATOR_ROLE) {
        _setCallbackGasLimit(_callbackGasLimit);
    }

    function setFailureHandleStrategy(uint8 _failureHandleStrategy) external onlyRole(OPERATOR_ROLE) {
        _setFailureHandleStrategy(_failureHandleStrategy);
    }

    /*----------------- internal functions -----------------*/
    function _buy(uint256 groupId, address refundAddress, uint256 amount) internal {
        address buyer = msg.sender;
        require(IERC1155NonTransferable(MEMBER_TOKEN).balanceOf(buyer, groupId) == 0, "MarketPlace: already purchased");

        address _owner = IERC721NonTransferable(GROUP_TOKEN).ownerOf(groupId);
        address[] memory members = new address[](1);
        members[0] = buyer;
        bytes memory callbackData = _encodeCallbackData(_owner, buyer, prices[groupId]);
        UpdateGroupSynPackage memory updatePkg = UpdateGroupSynPackage({
            operator: _owner,
            id: groupId,
            opType: UpdateGroupOpType.AddMembers,
            members: members,
            extraData: ""
        });
        ExtraData memory _extraData = ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: callbackData
        });

        IGroupHub(GROUP_HUB).updateGroup{value: amount}(updatePkg, callbackGasLimit, _extraData);
    }

    function _updateSales(uint256 groupId) internal {
        // 1. update sales volume
        salesVolume[groupId] += 1;

        uint256 _volume = salesVolume[groupId];
        for (uint256 i; i < _salesVolumeRanking.length; ++i) {
            if (_volume > _salesVolumeRanking[i]) {
                uint256 endIdx = _salesVolumeRanking.length - 1;
                for (uint256 j = i; j < _salesVolumeRanking.length; ++j) {
                    if (_salesVolumeRankingId[j] == groupId) {
                        endIdx = j;
                        break;
                    }
                }
                for (uint256 k = endIdx; k > i; --k) {
                    _salesVolumeRanking[k] = _salesVolumeRanking[k - 1];
                    _salesVolumeRankingId[k] = _salesVolumeRankingId[k - 1];
                }
                _salesVolumeRanking[i] = _volume;
                _salesVolumeRankingId[i] = groupId;
                break;
            }
        }

        // 2. update sales revenue
        uint256 _price = prices[groupId];
        salesRevenue[groupId] += _price;

        uint256 _revenue = salesRevenue[groupId];
        for (uint256 i; i < _salesRevenueRanking.length; ++i) {
            if (_revenue > _salesRevenueRanking[i]) {
                uint256 endIdx = _salesRevenueRanking.length - 1;
                for (uint256 j = i; j < _salesRevenueRanking.length; ++j) {
                    if (_salesRevenueRankingId[j] == groupId) {
                        endIdx = j;
                        break;
                    }
                }
                for (uint256 k = endIdx; k > i; --k) {
                    _salesRevenueRanking[k] = _salesRevenueRanking[k - 1];
                    _salesRevenueRankingId[k] = _salesRevenueRankingId[k - 1];
                }
                _salesRevenueRanking[i] = _revenue;
                _salesRevenueRankingId[i] = groupId;
                break;
            }
        }
    }

    function _groupGreenfieldCall(
        uint32 status,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) internal override {
        if (operationType == TYPE_UPDATE) {
            _updateGroupCallback(status, resourceId, callbackData);
        } else {
            revert("MarketPlace: invalid operation type");
        }
    }

    function _updateGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal override {
        (address owner, address buyer, uint256 price, bool ok) = _decodeCallbackData(_callbackData);
        if (!ok) {
            revert("MarketPlace: invalid callback data");
        }

        if (_status == STATUS_SUCCESS) {
            uint256 feeRateAmount = (price * feeRate) / 10_000;
            payable(fundWallet).transfer(feeRateAmount);
            (bool success,) = payable(owner).call{gas: transferGasLimit, value: price - feeRateAmount}("");
            if (!success) {
                _unclaimedFunds[owner] += price - feeRateAmount;
            }
            _userPurchasedGroups[buyer].add(_tokenId);
            _updateSales(_tokenId);
            emit Buy(buyer, _tokenId);
        } else {
            (bool success,) = payable(buyer).call{gas: transferGasLimit, value: price}("");
            if (!success) {
                _unclaimedFunds[buyer] += price;
            }
            emit BuyFailed(buyer, _tokenId);
        }
    }

    function _encodeCallbackData(address owner, address buyer, uint256 price) internal pure returns (bytes memory) {
        bytes[] memory elements = new bytes[](3);
        elements[0] = owner.encodeAddress();
        elements[1] = buyer.encodeAddress();
        elements[2] = price.encodeUint();
        return elements.encodeList();
    }

    function _decodeCallbackData(bytes memory _callbackData)
        internal
        pure
        returns (address owner, address buyer, uint256 price, bool success)
    {
        RLPDecode.Iterator memory iter = _callbackData.toRLPItem().iterator();

        uint256 idx;
        while (iter.hasNext()) {
            if (idx == 0) {
                owner = iter.next().toAddress();
            } else if (idx == 1) {
                buyer = iter.next().toAddress();
            } else if (idx == 2) {
                price = iter.next().toUint();
                success = true;
            } else {
                break;
            }
            idx++;
        }
    }

    // placeHolder reserved for future usage
    uint256[50] private __reservedSlots;
}
