// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../pool/interfaces/IPool.sol";

import "hardhat/console.sol";

/**
 * @notice Rewards Manager is responsible for accruing and distributing rewards for pool users.
 */
contract RewardsManager is Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet internal _activeRewards;
    mapping(IERC20 => address) internal _rewardHolders;

    struct PoolRewardsConfig {
        mapping(IERC20 => uint256) supplyRewardPerSecond;
        mapping(IERC20 => uint256) borrowRewardPerSecond;
    }
    mapping(IPool => PoolRewardsConfig) internal _poolRewardsConfig;

    struct PoolRewardsData {
        mapping(IERC20 => uint256) lastUpdate;
        mapping(IERC20 => uint256) supplyRewardPerShare;
        mapping(IERC20 => uint256) borrowRewardPerShare;
    }
    mapping(IPool => PoolRewardsData) internal _poolRewardsData;

    struct AccountData {
        mapping(IERC20 => uint256) supplyRewardPerShare;
        mapping(IERC20 => uint256) borrowRewardPerShare;
    }

    mapping(address => mapping(IPool => AccountData)) internal _accountsData;

    event Claim(address indexed account, uint256 amount);
    event RewardActivated(address indexed reward, address indexed holder);
    event RewardDeactivated(address indexed reward);
    event PoolRewardConfigUpdated(
        address indexed pool,
        address indexed reward,
        uint256 supplyRate,
        uint256 borrowRate
    );

    /**
     * @dev Precision by which to store accrued rewards
     */
    function accruedRewardsPrecision() public pure returns (uint256) {
        return 1e27;
    }

    /**
     * @notice Read all active rewards
     */
    function activeRewards() public view returns (address[] memory) {
        return _activeRewards.values();
    }

    /**
     * @notice Read holder for reward
     * @param reward - the reward for which to read the holder's address
     */
    function rewardHolder(IERC20 reward) public view returns (address) {
        return _rewardHolders[reward];
    }

    /**
     * @notice Read the reward configuration for a pool
     * @param pool - the pool of which to read the config
     * @param reward - the reward of which to read the config
     */
    function poolRewardConfig(IPool pool, IERC20 reward)
        public
        view
        returns (uint256, uint256)
    {
        PoolRewardsConfig storage poolConfig = _poolRewardsConfig[pool];
        uint256 supplyRatePerSecond = poolConfig.supplyRewardPerSecond[reward];
        uint256 borrowRatePerSecond = poolConfig.borrowRewardPerSecond[reward];
        return (supplyRatePerSecond, borrowRatePerSecond);
    }

    /**
     * @notice Read the rewards data for a pool
     * @param pool - the pool of which to read the data
     * @param reward - the reward of which to read the data
     */
    function poolRewardData(IPool pool, IERC20 reward)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        PoolRewardsData storage poolData = _poolRewardsData[pool];
        return (
            poolData.supplyRewardPerShare[reward],
            poolData.borrowRewardPerShare[reward],
            poolData.lastUpdate[reward]
        );
    }

    /**
     * @notice Read the reward data for a pool for an account
     * @param account - the account of which to read the data
     * @param pool - the pool of which to read the data
     * @param reward - the reward of which to read the data
     */
    function accountPoolRewardData(
        address account,
        IPool pool,
        IERC20 reward
    ) public view returns (uint256, uint256) {
        AccountData storage accountData = _accountsData[account][pool];
        return (
            accountData.supplyRewardPerShare[reward],
            accountData.borrowRewardPerShare[reward]
        );
    }

    /**
     * @notice Calculate new pool rewards per share data for a specified reward
     * @param pool - the pool of which to compute the data
     * @param reward - the reward of which to compute the data
     */
    function calculateNewRewardPerShareForPool(IPool pool, IERC20 reward)
        public
        view
        returns (uint256, uint256)
    {
        PoolRewardsConfig storage poolConfig = _poolRewardsConfig[pool];
        PoolRewardsData storage poolData = _poolRewardsData[pool];
        uint256 timeElapsed = block.timestamp - poolData.lastUpdate[reward];

        uint256 supplyRewardPerSharePerSecond = (poolConfig
            .supplyRewardPerSecond[reward] * accruedRewardsPrecision()) /
            pool.totalDeposits();

        uint256 borrowRewardPerSharePerSecond = (poolConfig
            .borrowRewardPerSecond[reward] * accruedRewardsPrecision()) /
            pool.totalLoans();

        uint256 newSupplyRewardPerShare = timeElapsed *
            supplyRewardPerSharePerSecond;
        uint256 newBorrowRewardPerShare = timeElapsed *
            borrowRewardPerSharePerSecond;

        return (newSupplyRewardPerShare, newBorrowRewardPerShare);
    }

    /**
     * @notice Update the accrued rewards pre share for a pool
     * @dev Normally called by the pool directly upon deposit/borrow/repay/withdraw or when updating the pool' reward config
     * @param poolAddress - the pool for which the rewards are accrued
     */
    function updatePoolRewardsData(address poolAddress) public {
        IPool pool = IPool(poolAddress);
        PoolRewardsConfig storage poolConfig = _poolRewardsConfig[pool];
        PoolRewardsData storage poolData = _poolRewardsData[pool];

        for (uint256 i = 0; i < _activeRewards.length(); i++) {
            IERC20 reward = IERC20(_activeRewards.at(i));

            uint256 timeElapsed = block.timestamp - poolData.lastUpdate[reward];

            uint256 supplyRewardPerSharePerSecond = (poolConfig
                .supplyRewardPerSecond[reward] * accruedRewardsPrecision()) /
                pool.totalDeposits();

            uint256 borrowRewardPerSharePerSecond = (poolConfig
                .borrowRewardPerSecond[reward] * accruedRewardsPrecision()) /
                pool.totalLoans();

            uint256 newSupplyRewardPerShare = timeElapsed *
                supplyRewardPerSharePerSecond;
            uint256 newBorrowRewardPerShare = timeElapsed *
                borrowRewardPerSharePerSecond;

            poolData.supplyRewardPerShare[reward] = newSupplyRewardPerShare;
            poolData.borrowRewardPerShare[reward] = newBorrowRewardPerShare;

            poolData.lastUpdate[reward] = block.timestamp;
        }
    }

    /**
     * @notice Claim reward
     * @dev Caller needs to pass which pools to claim for
     * @param reward - the reward to claim
     * @param pools - list of pools for which to update the accrued rewards before claiming - normally all of them
     */
    function claimForPools(IERC20 reward, address[] memory pools) public {
        address account = _msgSender();
        uint256 toClaim;

        for (uint256 i = 0; i < pools.length; i++) {
            IPool pool = IPool(pools[i]);
            AccountData storage accountData = _accountsData[account][pool];
            PoolRewardsData storage poolData = _poolRewardsData[pool];

            uint256 supplyDelta = poolData.supplyRewardPerShare[reward] -
                accountData.supplyRewardPerShare[reward];
            uint256 borrowDelta = poolData.borrowRewardPerShare[reward] -
                accountData.borrowRewardPerShare[reward];

            uint256 toAdd = supplyDelta * pool.accountDepositAmount(account);
            toAdd += borrowDelta * pool.accountDebtAmount(account);

            toClaim += toAdd / 1 ether;

            accountData.supplyRewardPerShare[reward] = poolData
                .supplyRewardPerShare[reward];
            accountData.borrowRewardPerShare[reward] = poolData
                .borrowRewardPerShare[reward];
        }

        toClaim = toClaim / accruedRewardsPrecision();
        console.log("toClaim=%s", toClaim);

        reward.safeTransferFrom(_rewardHolders[reward], account, toClaim);

        emit Claim(account, toClaim);
    }

    // ---------ADMIN METHODS

    /**
     * @notice Update a pool's reward configuration
     * @param pool - the pool for which to update the config
     * @param reward - the reward for which to update the config
     * @param supplyRate - the new supplyRatePerSecond
     * @param borrowRate - the new borrowRatePerSecond
     */
    function updatePoolRewardConfig(
        IPool pool,
        IERC20 reward,
        uint256 supplyRate,
        uint256 borrowRate
    ) public onlyOwner {
        updatePoolRewardsData(address(pool));

        PoolRewardsConfig storage poolConfig = _poolRewardsConfig[pool];
        poolConfig.supplyRewardPerSecond[reward] = supplyRate;
        poolConfig.borrowRewardPerSecond[reward] = borrowRate;

        emit PoolRewardConfigUpdated(
            address(pool),
            address(reward),
            supplyRate,
            borrowRate
        );
    }

    /**
     * @notice Activate reward
     * @dev Requires allowance to be set by rewardHolder.
     * Remember to update pool configs as well.
     * @param reward - the reward to start distributing
     * @param rewardHolder_ - the address holding the reward balance (can be this contract)
     */
    function activateReward(IERC20 reward, address rewardHolder_)
        public
        onlyOwner
    {
        _activeRewards.add(address(reward));
        _rewardHolders[reward] = rewardHolder_;
        uint256 allowance = reward.allowance(rewardHolder_, address(this));
        require(
            allowance ==
                uint256(
                    0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
                ),
            "ACTIVATE REWARD: Allowance too small"
        );
        emit RewardActivated(address(reward), rewardHolder_);
    }

    /**
     * @notice Deactivate reward
     * Users will still be able to claim
     * @param reward - the reward to deactivate
     */
    function deactivateReward(address reward) public onlyOwner {
        _activeRewards.remove(reward);
        emit RewardDeactivated(reward);
    }
}
