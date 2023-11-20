// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IMarketplace {
    event AppHandleAckPkgFailed(address indexed appAddress, bytes32 pkgHash, bytes failReason);
    event AppHandleFailAckPkgFailed(address indexed appAddress, bytes32 pkgHash, bytes failReason);
    event Buy(address indexed buyer, uint256 indexed groupId);
    event BuyFailed(address indexed buyer, uint256 indexed groupId);
    event CreateFailed(address indexed creator, uint256 indexed id);
    event CreateGroupFailed(uint32 status, bytes groupName);
    event CreateGroupSuccess(bytes groupName, uint256 indexed tokenId);
    event CreateSubmitted(address indexed owner, address indexed operator, string name);
    event CreateSuccess(address indexed creator, uint256 indexed id);
    event DeleteFailed(uint256 indexed id);
    event DeleteGroupFailed(uint32 status, uint256 indexed tokenId);
    event DeleteGroupSuccess(uint256 indexed tokenId);
    event DeleteSubmitted(address indexed owner, address indexed operator, uint256 indexed id);
    event DeleteSuccess(uint256 indexed id);
    event Delist(address indexed owner, uint256 indexed groupId);
    event FailAckPkgReceived(uint8 indexed channelId, bytes msgBytes);
    event Initialized(uint8 version);
    event List(address indexed owner, uint256 indexed groupId, uint256 price);
    event MirrorFailed(uint256 indexed id, address indexed owner, bytes failReason);
    event MirrorSuccess(uint256 indexed id, address indexed owner);
    event ParamChange(string key, bytes value);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event UnexpectedPackage(uint8 indexed channelId, bytes msgBytes);
    event UpdateFailed(address indexed operator, uint256 indexed id, uint8 opType);
    event UpdateGroupFailed(uint32 status, uint256 indexed tokenId);
    event UpdateGroupSuccess(uint256 indexed tokenId);
    event UpdateSubmitted(address owner, address operator, uint256 id, uint8 opType, address[] members);
    event UpdateSuccess(address indexed operator, uint256 indexed id, uint8 opType);
    event PriceUpdated(address indexed owner, uint256 indexed groupId, uint256 price);
    event Star(address indexed user, uint256 indexed groupId);
    event Sponsor(address indexed sponsor, uint256 indexed groupId, uint256 amount);
    event Rate(address indexed buyer, uint256 indexed groupId, uint256 score);

    function AUTH_CODE_CREATE() external view returns (uint32);
    function AUTH_CODE_DELETE() external view returns (uint32);
    function AUTH_CODE_UPDATE() external view returns (uint32);
    function BUCKET_CHANNEL_ID() external view returns (uint8);
    function BUCKET_HUB() external view returns (address);
    function CROSS_CHAIN() external view returns (address);
    function CmnStorageSlots(uint256) external view returns (uint256);
    function ConfigSlots(uint256) external view returns (uint256);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function ERC1155Token() external view returns (address);
    function ERC721Token() external view returns (address);
    function ERROR_INSUFFICIENT_VALUE() external view returns (string memory);
    function ERROR_INVALID_CALLER() external view returns (string memory);
    function ERROR_INVALID_OPERATION() external view returns (string memory);
    function ERROR_INVALID_RESOURCE() external view returns (string memory);
    function GOV_CHANNEL_ID() external view returns (uint8);
    function GOV_HUB() external view returns (address);
    function GROUP_CHANNEL_ID() external view returns (uint8);
    function GROUP_HUB() external view returns (address);
    function GROUP_TOKEN() external view returns (address);
    function MEMBER_TOKEN() external view returns (address);
    function GroupStorageSlots(uint256) external view returns (uint256);
    function LIGHT_CLIENT() external view returns (address);
    function OBJECT_CHANNEL_ID() external view returns (uint8);
    function OBJECT_HUB() external view returns (address);
    function OPERATOR_ROLE() external view returns (bytes32);
    function PROXY_ADMIN() external view returns (address);
    function PkgQueueSlots(uint256) external view returns (uint256);
    function RELAYER_HUB() external view returns (address);
    function RESOURCE_GROUP() external view returns (uint8);
    function ROLE_CREATE() external view returns (bytes32);
    function ROLE_DELETE() external view returns (bytes32);
    function ROLE_UPDATE() external view returns (bytes32);
    function STATUS_FAILED() external view returns (uint32);
    function STATUS_SUCCESS() external view returns (uint32);
    function STATUS_UNEXPECTED() external view returns (uint32);
    function TOKEN_HUB() external view returns (address);
    function TRANSFER_IN_CHANNEL_ID() external view returns (uint8);
    function TRANSFER_OUT_CHANNEL_ID() external view returns (uint8);
    function TYPE_CREATE() external view returns (uint8);
    function TYPE_DELETE() external view returns (uint8);
    function TYPE_MIRROR() external view returns (uint8);
    function TYPE_UPDATE() external view returns (uint8);
    function _CROSS_CHAIN() external view returns (address);
    function _GROUP_HUB() external view returns (address);
    function _GROUP_TOKEN() external view returns (address);
    function _MEMBER_TOKEN() external view returns (address);
    function addOperator(address newOperator) external;
    function additional() external view returns (address);
    function buy(uint256 groupId, address refundAddress) external payable;
    function buyBatch(uint256[] memory groupIds, address refundAddress) external payable;
    function star(uint256 groupId) external;
    function sponsor(uint256 groupId) external payable;
    function rate(uint256 groupId, uint256 score) external;
    function callbackGasLimit() external view returns (uint256);
    function channelId() external view returns (uint8);
    function claim() external;
    function crossChain() external view returns (address);
    function delist(uint256 groupId) external;
    function failureHandleStrategy() external view returns (uint8);
    function feeRate() external view returns (uint256);
    function fundWallet() external view returns (address);
    function getListed(
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory _ids, uint256[] memory _dates, uint256 _totalLength);
    function getMinRelayFee() external returns (uint256 amount);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function getSalesRevenue(
        uint256 offset,
        uint256 limit
    )
        external
        view
        returns (uint256[] memory _ids, uint256[] memory _revenues, uint256[] memory _dates, uint256 _totalLength);
    function getSalesRevenueRanking()
        external
        view
        returns (uint256[] memory _ids, uint256[] memory _revenues, uint256[] memory _dates);
    function getSalesVolume(
        uint256 offset,
        uint256 limit
    )
        external
        view
        returns (uint256[] memory _ids, uint256[] memory _volumes, uint256[] memory _dates, uint256 _totalLength);
    function getSalesVolumeRanking()
        external
        view
        returns (uint256[] memory _ids, uint256[] memory _volumes, uint256[] memory _dates);
    function getStars(
        uint256 offset,
        uint256 limit
    )
    external
    view
    returns (uint256[] memory _ids, uint256[] memory _stars, uint256[] memory _dates, uint256 _totalLength);
    function getStarsRanking()
        external
        view
        returns (uint256[] memory _ids, uint256[] memory _stars, uint256[] memory _dates);
    function getSponsorRevenue(
        uint256 offset,
        uint256 limit
    )
    external
    view
    returns (uint256[] memory _ids, uint256[] memory _revenues, uint256[] memory _dates, uint256 _totalLength);
    function getSponsorRevenueRanking()
        external
        view
        returns (uint256[] memory _ids, uint256[] memory _revenues, uint256[] memory _dates);
    function getUnclaimedAmount() external view returns (uint256 amount);
    function getUserListed(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory _ids, uint256[] memory _dates, uint256 _totalLength);
    function getUserPurchased(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory _ids, uint256[] memory _dates, uint256 _totalLength);
    function getUserStared(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory _ids, uint256[] memory _dates, uint256 _totalLength);
    function getUserSponsored(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory _ids, uint256[] memory _dates, uint256 _totalLength);
    function getUserRated(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory _ids, uint256[] memory _dates, uint256 _totalLength);
    function hasUserRated(address user, uint256 groupId) external view returns(bool);
    function grantRole(bytes32 role, address account) external;
    function greenfieldCall(
        uint32 status,
        uint8 resourceType,
        uint8 operationType,
        uint256 resourceId,
        bytes memory callbackData
    ) external;
    function groupHub() external view returns (address);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function initialize(
        address _initAdmin,
        address _fundWallet,
        uint256 _feeRate,
        uint256 _callbackGasLimit,
        uint8 _failureHandleStrategy
    ) external;
    function list(uint256 groupId, uint256 price) external;
    function listedDate(uint256) external view returns (uint256);
    function packageMap(bytes32)
    external
    view
    returns (
        address appAddress,
        uint32 status,
        uint8 operationType,
        uint256 resourceId,
        bytes memory callbackData,
        bytes memory failReason
    );
    function prices(uint256) external view returns (uint256);
    function scores(uint256) external view returns (uint256);
    function removeOperator(address operator) external;
    function renounceRole(bytes32 role, address account) external;
    function retryPackage(uint8) external;
    function retryQueue(address) external view returns (int128 _begin, int128 _end);
    function revokeRole(bytes32 role, address account) external;
    function salesRevenue(uint256) external view returns (uint256);
    function salesVolume(uint256) external view returns (uint256);
    function stars(uint256) external view returns (uint256);
    function sponsorRevenue(uint256) external view returns (uint256);
    function setCallbackGasLimit(uint256 _callbackGasLimit) external;
    function setFailureHandleStrategy(uint8 _failureHandleStrategy) external;
    function setFeeRate(uint256 _feeRate) external;
    function setFundWallet(address _fundWallet) external;
    function setPrice(uint256 groupId, uint256 newPrice) external;
    function skipPackage(uint8) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function transferGasLimit() external view returns (uint256);
    function versionInfo() external pure returns (uint256 version, string memory name, string memory description);
}
