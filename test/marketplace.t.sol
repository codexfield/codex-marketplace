// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "@bnb-chain/greenfield-contracts-sdk/interface/IGroupHub.sol";

import "../contracts/deployer.sol";
import "../contracts/interface/IMarketplace.sol";

interface IERC721 {
    function mint(address to, uint256 tokenId) external;
}

contract MarketplaceTest is Test {
    uint256 public constant callbackGasLimit = 1_000_000; // TODO: TBD
    uint8 public constant failureHandleStrategy = 0; // BlockOnFail
    uint256 public constant tax = 100; // 1%

    address public operator;
    address public proxyMarketplace;

    address public owner;
    address public crossChain;
    address public groupHub;
    address public groupToken;

    event List(address indexed owner, uint256 indexed groupId, uint256 price);
    event Delist(address indexed owner, uint256 indexed groupId);
    event UpdateSubmitted(address owner, address operator, uint256 id, uint8 opType, address[] members);

    receive() external payable {}

    function setUp() public {
        uint256 privateKey = uint256(vm.envBytes32("OWNER_PRIVATE_KEY"));
        owner = vm.addr(privateKey);
        console.log("owner: %s", owner);

        proxyMarketplace = 0x90DEFDB65A73717A36f732C2Ae218f7DcaBF17a0; // get this from deploy script's log
        crossChain = IMarketplace(proxyMarketplace).CROSS_CHAIN();
        groupHub = IMarketplace(proxyMarketplace).GROUP_HUB();
        groupToken = IMarketplace(proxyMarketplace).GROUP_TOKEN();
    }

    function testList(uint256 tokenId) public {
        vm.assume(!IERC721NonTransferable(groupToken).exists(tokenId));

        // failed with unexisted group
        vm.expectRevert("ERC721: invalid token ID");
        IMarketplace(proxyMarketplace).list(tokenId, 1e18);

        vm.startPrank(groupHub);
        IERC721(groupToken).mint(address(this), tokenId);
        vm.stopPrank();

        // failed with not group owner
        vm.startPrank(address(0x1234));
        vm.expectRevert("MarketPlace: only group owner");
        IMarketplace(proxyMarketplace).list(tokenId, 1e18);
        vm.stopPrank();

        // success case
        IGroupHub(groupHub).grant(proxyMarketplace, 4, 0);
        vm.expectEmit(true, true, false, true, proxyMarketplace);
        emit List(address(this), tokenId, 1e18);
        IMarketplace(proxyMarketplace).list(tokenId, 1e18);
    }

    function testDelist(uint256 tokenId) public {
        vm.assume(!IERC721NonTransferable(groupToken).exists(tokenId));

        vm.prank(groupHub);
        IERC721(groupToken).mint(address(this), tokenId);

        // failed with not listed group
        vm.expectRevert("MarketPlace: not listed");
        IMarketplace(proxyMarketplace).delist(tokenId);

        IGroupHub(groupHub).grant(proxyMarketplace, 4, 0);
        IMarketplace(proxyMarketplace).list(tokenId, 1e18);

        // failed with not group owner
        vm.startPrank(address(0x1234));
        vm.expectRevert("MarketPlace: only group owner");
        IMarketplace(proxyMarketplace).delist(tokenId);
        vm.stopPrank();

        // success case
        vm.expectEmit(true, true, false, true, proxyMarketplace);
        emit Delist(address(this), tokenId);
        IMarketplace(proxyMarketplace).delist(tokenId);
    }

    function testBuy(uint256 tokenId) public {
        vm.assume(!IERC721NonTransferable(groupToken).exists(tokenId));

        address _owner = address(0x1234);
        uint256 relayFee = _getTotalFee();
        // address _buyer = address(this);

        // failed with not listed group
        vm.expectRevert("MarketPlace: not listed");
        IMarketplace(proxyMarketplace).buy(tokenId, address(this));

        vm.prank(groupHub);
        IERC721(groupToken).mint(_owner, tokenId);
        vm.startPrank(_owner);
        IGroupHub(groupHub).grant(proxyMarketplace, 4, 0);
        IMarketplace(proxyMarketplace).list(tokenId, 1e18);
        vm.stopPrank();

        // failed with not enough fund
        vm.expectRevert("MarketPlace: insufficient fund");
        IMarketplace(proxyMarketplace).buy{value: 1 ether}(tokenId, address(this));

        // success case
        address[] memory members = new address[](1);
        members[0] = address(this);
        vm.expectEmit(true, true, true, true, groupHub);
        emit UpdateSubmitted(_owner, proxyMarketplace, tokenId, 0, members);
        IMarketplace(proxyMarketplace).buy{value: 1e18 + relayFee}(tokenId, address(this));
    }

    function testVerify() public {
        address _impl = 0xE18Ec43451B0723Ede72A49d5D74fA9933Ddc46f;
        address _owner = 0x079F289Bb65c4E336c57E394E4961031FbC91313;
        string memory _str = "";
        bytes memory _data = abi.encode(_impl, _owner, _str);
        emit log_bytes(_data);
    }

    function _getTotalFee() internal returns (uint256) {
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(crossChain).getRelayFees();
        uint256 gasPrice = ICrossChain(crossChain).callbackGasPrice();
        return relayFee + minAckRelayFee + callbackGasLimit * gasPrice;
    }
}
