// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@bnb-chain/greenfield-contracts/contracts/interface/IERC721NonTransferable.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IERC1155NonTransferable.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IGnfdAccessControl.sol";
import "@bnb-chain/greenfield-contracts-sdk/GroupApp.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableMapUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/DoubleEndedQueueUpgradeable.sol";

contract Marketplace is ReentrancyGuard, AccessControl, GroupApp {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;

    /*----------------- constants -----------------*/
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // greenfield system contracts
    address public constant _CROSS_CHAIN = 0xa5B2c9194131A4E0BFaCbF9E5D6722c873159cb7;
    address public constant _GROUP_HUB = 0x50B3BF0d95a8dbA57B58C82dFDB5ff6747Cc1a9E;
    address public constant _GROUP_TOKEN = 0x7fC61D6FCA8D6Ea811637bA58eaf6aB17d50c4d1;
    address public constant _MEMBER_TOKEN = 0x43bdF3d63e6318A2831FE1116cBA69afd0F05267;

    /*----------------- storage -----------------*/
    // group ID => item price
    mapping(uint256 => uint256) public prices;
    // group ID => listed date
    mapping(uint256 => uint256) public listedDate;
    // group ID => total sales volume
    mapping(uint256 => uint256) public salesVolume;
    // group ID => total sales revenue
    mapping(uint256 => uint256) public salesRevenue;
    // group ID => total stars
    mapping(uint256 => uint256) public stars;
    // group ID => total sponsor revenue
    mapping(uint256 => uint256) public sponsorRevenue;
    // group ID => scores 0~127: average score 128~255: score counts
    mapping(uint256 => uint256) public scores;

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

    // stars ranking list, ordered by stars number(desc)
    uint256[] private _starsRanking;
    // group ID corresponding to the stars ranking list, ordered by stars number(desc)
    uint256[] private _starsRankingId;

    // sponsor revenue ranking list, ordered by sponsor revenue(desc)
    uint256[] private _sponsorRevenueRanking;
    // group ID corresponding to the sponsor revenue ranking list, ordered by sponsor revenue(desc)
    uint256[] private _sponsorRevenueRankingId;

    // user address => user listed group IDs, ordered by listed time
    mapping(address => EnumerableSetUpgradeable.UintSet) private _userListedGroups;
    // user address => user purchased group IDs, ordered by purchased time
    mapping(address => EnumerableSetUpgradeable.UintSet) private _userPurchasedGroups;
    // user address => user stared group IDs, ordered by star time
    mapping(address => EnumerableSetUpgradeable.UintSet) private _userStaredGroups;
    // user address => user sponsored group IDs, ordered by sponsor time
    mapping(address => EnumerableSetUpgradeable.UintSet) private _userSponsoredGroups;
    // user address => user rated group IDs, ordered by rated time
    mapping(address => EnumerableSetUpgradeable.UintSet) private _userRatedGroups;

    address public fundWallet;

    uint256 public transferGasLimit; // 2300 for now
    uint256 public feeRate; // 10000 = 100%

    /*----------------- event/modifier -----------------*/
    event List(address indexed owner, uint256 indexed groupId, uint256 price);
    event Delist(address indexed owner, uint256 indexed groupId);
    event Buy(address indexed buyer, uint256 indexed groupId);
    event BuyFailed(address indexed buyer, uint256 indexed groupId);
    event PriceUpdated(address indexed owner, uint256 indexed groupId, uint256 price);
    event Star(address indexed user, uint256 indexed groupId);
    event Sponsor(address indexed sponsor, uint256 indexed groupId, uint256 amount);
    event Rate(address indexed buyer, uint256 indexed groupId, uint256 score);

    modifier onlyGroupOwner(uint256 groupId) {
        require(msg.sender == IERC721NonTransferable(_GROUP_TOKEN).ownerOf(groupId), "MarketPlace: only group owner");
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

        __base_app_init_unchained(_CROSS_CHAIN, _callbackGasLimit, _failureHandleStrategy);
        __group_app_init_unchained(_GROUP_HUB);

        // init ranking arrays
        _salesVolumeRanking = new uint256[](10);
        _salesVolumeRankingId = new uint256[](10);
        _salesRevenueRanking = new uint256[](10);
        _salesRevenueRankingId = new uint256[](10);
        _starsRanking = new uint256[](10);
        _starsRankingId = new uint256[](10);
        _sponsorRevenueRanking = new uint256[](10);
        _sponsorRevenueRankingId = new uint256[](10);
    }

    /*----------------- external functions -----------------*/
    function greenfieldCall(
        uint32 status,
        uint8 resourceType,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external override(GroupApp) {
        require(msg.sender == _GROUP_HUB, "MarketPlace: invalid caller");

        if (resourceType == RESOURCE_GROUP) {
            _groupGreenfieldCall(status, operationType, resourceId, callbackData);
        } else {
            revert("MarketPlace: invalid resource type");
        }
    }

    function list(uint256 groupId, uint256 price) external onlyGroupOwner(groupId) {
        // the owner need to approve the marketplace contract to update the group
        require(IGnfdAccessControl(_GROUP_HUB).hasRole(ROLE_UPDATE, msg.sender, address(this)), "Marketplace: no grant");
        require(!_listedGroups.contains(groupId), "Marketplace: already listed");

        prices[groupId] = price;
        listedDate[groupId] = block.timestamp;
        _listedGroups.add(groupId);
        _userListedGroups[msg.sender].add(groupId);

        emit List(msg.sender, groupId, price);
    }

    function setPrice(uint256 groupId, uint256 newPrice) external onlyGroupOwner(groupId) {
        require(_listedGroups.contains(groupId), "MarketPlace: not listed");
        prices[groupId] = newPrice;
        emit PriceUpdated(msg.sender, groupId, newPrice);
    }

    function delist(uint256 groupId) external onlyGroupOwner(groupId) {
        require(_listedGroups.contains(groupId), "MarketPlace: not listed");

        delete prices[groupId];
        delete listedDate[groupId];
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

        for (uint256 i; i < _starsRankingId.length; ++i) {
            if (_starsRankingId[i] == groupId) {
                for (uint256 j = i; j < _starsRankingId.length - 1; ++j) {
                    _starsRankingId[j] = _starsRankingId[j + 1];
                    _starsRanking[j] = _starsRanking[j + 1];
                }
                _starsRankingId[_starsRankingId.length - 1] = 0;
                _starsRanking[_starsRankingId.length - 1] = 0;
                break;
            }
        }

        for (uint256 i; i < _sponsorRevenueRankingId.length; ++i) {
            if (_sponsorRevenueRankingId[i] == groupId) {
                for (uint256 j = i; j < _sponsorRevenueRankingId.length - 1; ++j) {
                    _sponsorRevenueRankingId[j] = _sponsorRevenueRankingId[j + 1];
                    _sponsorRevenueRanking[j] = _sponsorRevenueRanking[j + 1];
                }
                _sponsorRevenueRankingId[_sponsorRevenueRankingId.length - 1] = 0;
                _sponsorRevenueRanking[_sponsorRevenueRankingId.length - 1] = 0;
                break;
            }
        }

        emit Delist(msg.sender, groupId);
    }

    function buy(uint256 groupId, address refundAddress) external payable {
        uint256 price = prices[groupId];
        require(price > 0, "MarketPlace: not listed for sale");
        require(!_userPurchasedGroups[msg.sender].contains(groupId), "MarketPlace: already purchased");
        require(msg.value >= prices[groupId] + _getTotalFee(), "MarketPlace: insufficient fund");

        _buy(groupId, refundAddress, msg.value - price);
    }

    function buyBatch(uint256[] calldata groupIds, address refundAddress) external payable {
        uint256 receivedValue = msg.value;
        uint256 relayFee = _getTotalFee();
        uint256 amount;
        for (uint256 i; i < groupIds.length; ++i) {
            require(prices[groupIds[i]] > 0, "MarketPlace: not listed for sale");
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

    function star(uint256 groupId) external {
        require(_listedGroups.contains(groupId), "MarketPlace: not listed");
        require(!_userStaredGroups[msg.sender].contains(groupId), "MarketPlace: already stared");

        _updateStars(groupId);

        _userStaredGroups[msg.sender].add(groupId);
        emit Star(msg.sender, groupId);
    }

    function sponsor(uint256 groupId) external payable {
        require(_listedGroups.contains(groupId), "MarketPlace: not listed");
        require(msg.value > 0, "MarketPlace: invalid amount");

        _updateSponsorRevenue(groupId, msg.value);

        _userSponsoredGroups[msg.sender].add(groupId);
        emit Sponsor(msg.sender, groupId, msg.value);
    }

    function rate(uint256 groupId, uint256 score) external {
        require(_userPurchasedGroups[msg.sender].contains(groupId), "MarketPlace: not purchased");
        require(!_userRatedGroups[msg.sender].contains(groupId), "MarketPlace: already rated");
        require(score <= 5e18, "MarketPlace: invalid score");

        uint256 _score = scores[groupId] & 0xffffffffffffffffffffffffffffffff;
        uint256 _count = scores[groupId] >> 128;
        uint256 totalScore = _score*_count + score;
        _count += 1;
        _score = totalScore / _count;
        scores[groupId] = (_count << 128) + _score;

        _userRatedGroups[msg.sender].add(groupId);
        emit Rate(msg.sender, groupId, score);
    }

    /*----------------- view functions -----------------*/
    function versionInfo()
    external
    pure
    override
    returns (uint256 version, string memory name, string memory description)
    {
        return (1, "MarketPlace", "support greenfield-contracts v0.0.9-alpha3");
    }

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

    function getStarsRanking()
    external
    view
    returns (uint256[] memory _ids, uint256[] memory _stars, uint256[] memory _dates)
    {
        _ids = _starsRankingId;
        _stars = _starsRanking;

        _dates = new uint256[](_ids.length);
        for (uint256 i; i < _ids.length; ++i) {
            _dates[i] = listedDate[_ids[i]];
        }
    }

    function getSponsorRevenueRanking()
    external
    view
    returns (uint256[] memory _ids, uint256[] memory _revenues, uint256[] memory _dates)
    {
        _ids = _sponsorRevenueRankingId;
        _revenues = _sponsorRevenueRanking;

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

    function getStars(
        uint256 offset,
        uint256 limit
    )
    external
    view
    returns (uint256[] memory _ids, uint256[] memory _stars, uint256[] memory _dates, uint256 _totalLength) {
        _totalLength = _listedGroups.length();
        if (offset >= _totalLength) {
            return (_ids, _stars, _dates, _totalLength);
        }

        uint256 count = _totalLength - offset;
        if (count > limit) {
            count = limit;
        }
        _ids = new uint256[](count);
        _stars = new uint256[](count);
        _dates = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            _ids[i] = _listedGroups.at(offset + i);
            _stars[i] = stars[_ids[i]];
            _dates[i] = listedDate[_ids[i]];
        }
    }

    function getSponsorRevenue(
        uint256 offset,
        uint256 limit
    )
    external
    view
    returns (uint256[] memory _ids, uint256[] memory _revenues, uint256[] memory _dates, uint256 _totalLength) {
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
            _revenues[i] = sponsorRevenue[_ids[i]];
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

    function getUserStared(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory _ids, uint256[] memory _dates, uint256 _totalLength) {
        _totalLength = _userStaredGroups[user].length();
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
            _ids[i] = _userStaredGroups[user].at(offset + i);
            _dates[i] = listedDate[_ids[i]];
        }
    }

    function getUserSponsored(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory _ids, uint256[] memory _dates, uint256 _totalLength) {
        _totalLength = _userSponsoredGroups[user].length();
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
            _ids[i] = _userSponsoredGroups[user].at(offset + i);
            _dates[i] = listedDate[_ids[i]];
        }
    }

    function getUserRated(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory _ids, uint256[] memory _dates, uint256 _totalLength) {
        _totalLength = _userRatedGroups[user].length();
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
            _ids[i] = _userRatedGroups[user].at(offset + i);
            _dates[i] = listedDate[_ids[i]];
        }
    }

    function hasUserRated(address user, uint256 groupId) external view returns(bool) {
        return _userRatedGroups[user].contains(groupId);
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
        require(IERC1155NonTransferable(_MEMBER_TOKEN).balanceOf(buyer, groupId) == 0, "MarketPlace: already purchased");

        address _owner = IERC721NonTransferable(_GROUP_TOKEN).ownerOf(groupId);
        address[] memory members = new address[](1);
        uint64[] memory expirations = new uint64[](1);
        members[0] = buyer;
        expirations[0] = 0;
        bytes memory callbackData = abi.encode(_owner, buyer, prices[groupId]);
        UpdateGroupSynPackage memory updatePkg = UpdateGroupSynPackage({
            operator: _owner,
            id: groupId,
            opType: UpdateGroupOpType.AddMembers,
            members: members,
            extraData: "",
            memberExpiration: expirations
        });
        ExtraData memory _extraData = ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: callbackData
        });

        IGroupHub(_GROUP_HUB).updateGroup{value: amount}(updatePkg, callbackGasLimit, _extraData);
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

    function _updateStars(uint256 groupId) internal {
        stars[groupId] += 1;
        uint256 _stars = stars[groupId];
        for (uint256 i; i < _starsRanking.length; ++i) {
            if (_stars > _starsRanking[i]) {
                uint256 endIdx = _starsRanking.length - 1;
                for (uint256 j = i; j < _starsRanking.length; ++j) {
                    if (_starsRankingId[j] == groupId) {
                        endIdx = j;
                        break;
                    }
                }
                for (uint256 k = endIdx; k > i; --k) {
                    _starsRanking[k] = _starsRanking[k - 1];
                    _starsRankingId[k] = _starsRankingId[k - 1];
                }
                _starsRanking[i] = _stars;
                _starsRankingId[i] = groupId;
                break;
            }
        }
    }

    function _updateSponsorRevenue(uint256 groupId, uint256 amount) internal {
        sponsorRevenue[groupId] += amount;
        uint256 _revenue = sponsorRevenue[groupId];
        for (uint256 i; i < _sponsorRevenueRanking.length; ++i) {
            if (_revenue > _sponsorRevenueRanking[i]) {
                uint256 endIdx = _sponsorRevenueRanking.length - 1;
                for (uint256 j = i; j < _sponsorRevenueRanking.length; ++j) {
                    if (_sponsorRevenueRankingId[j] == groupId) {
                        endIdx = j;
                        break;
                    }
                }
                for (uint256 k = endIdx; k > i; --k) {
                    _sponsorRevenueRanking[k] = _sponsorRevenueRanking[k - 1];
                    _sponsorRevenueRankingId[k] = _sponsorRevenueRankingId[k - 1];
                }
                _sponsorRevenueRanking[i] = _revenue;
                _sponsorRevenueRankingId[i] = groupId;
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
        (address owner, address buyer, uint256 price) = abi.decode(_callbackData, (address, address, uint256));

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

    // placeHolder reserved for future usage
    uint256[50] private __reservedSlots;
}
