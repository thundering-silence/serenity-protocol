// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../../IOwnable.sol";
import "../../pool/interfaces/IPool.sol";

interface IRewardsManager is IOwnable {
    function accruedRewardsPrecision() external pure returns (uint256);

    function activeRewards() external view returns (address[] memory);

    function rewardHolder(IERC20 reward) external view returns (address);

    function poolRewardConfig(IPool pool, IERC20 reward)
        external
        view
        returns (uint256, uint256);

    function calculateNewRewardPerShareForPool(IPool pool, IERC20 reward)
        external
        view
        returns (uint256, uint256);

    function updatePoolRewardsData(address poolAddress) external;

    function claimForPools(IERC20 reward, IPool[] memory pools) external;

    function activateReward(IERC20 reward, address rewardHolder_) external;

    function deactivateReward(address reward) external;

    function updatePoolRewardConfig(
        IPool pool,
        IERC20 reward,
        uint256 supplyRate,
        uint256 borrowRate
    ) external;
}
