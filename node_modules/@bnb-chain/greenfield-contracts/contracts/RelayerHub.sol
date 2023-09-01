// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./Config.sol";
import "./interface/ITokenHub.sol";
import "./interface/ILightClient.sol";
import "./interface/IRelayerHub.sol";

contract RelayerHub is Config, ReentrancyGuardUpgradeable, IRelayerHub {
    uint256 public constant REWARD_RATIO_SCALE = 100;

    /*----------------- storage layer -----------------*/
    mapping(address => uint256) public rewardMap;

    /*----------------- event -----------------*/
    event RewardToRelayer(address relayer, uint256 amount);
    event ClaimedReward(address relayer, uint256 amount);

    /*----------------- external function -----------------*/
    receive() external payable {
        require(msg.sender == TOKEN_HUB, "only receive from token hub");
    }

    function initialize() public initializer {
        __ReentrancyGuard_init();
    }

    function addReward(address _relayer, uint256 _reward) external onlyCrossChain {
        uint256 actualAmount = ITokenHub(TOKEN_HUB).claimRelayFee(_reward);
        rewardMap[_relayer] += actualAmount;
        emit RewardToRelayer(_relayer, actualAmount);
    }

    function claimReward(address payable _relayer) external nonReentrant {
        uint256 _reward = rewardMap[_relayer];
        require(_reward > 0, "no relayer reward");
        rewardMap[_relayer] = 0;

        require(address(this).balance >= _reward, "relayer reward not enough");
        _relayer.transfer(_reward);
        emit ClaimedReward(_relayer, _reward);
    }

    function versionInfo()
        external
        pure
        override
        returns (uint256 version, string memory name, string memory description)
    {
        return (500_001, "RelayerHub", "init version");
    }
}
