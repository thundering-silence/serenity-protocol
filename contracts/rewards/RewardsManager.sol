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

    struct AccountData {
        uint256 lastUpdate;
        mapping(IERC20 => uint256) accruedRewards;
    }
    mapping(address => AccountData) internal _accountsData;

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
     * @notice Easy way of getting the reward configuration for a pool
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
     * @notice Update the accrued rewards for and account from a pool
     * @dev Normally called by the pool directly upon deposit/borrow/repay/withdraw
     * @param account - the account for which to update rewards
     * @param poolAddress - the pool from which the rewards come from
     */
    function updateAccountRewards(address account, address poolAddress) public {
        IPool pool = IPool(poolAddress);
        PoolRewardsConfig storage poolConfig = _poolRewardsConfig[pool];
        AccountData storage data = _accountsData[account];

        uint256 timePassed = block.timestamp - data.lastUpdate;

        for (uint16 i = 0; i < _activeRewards.length(); i++) {
            IERC20 reward = IERC20(_activeRewards.at(i));

            uint256 totalSupplyRewards = timePassed *
                poolConfig.supplyRewardPerSecond[reward];
            uint256 totalBorrowRewards = timePassed *
                poolConfig.borrowRewardPerSecond[reward];

            uint256 accountSupplyWeight = (pool.accountDepositAmount(account) *
                accruedRewardsPrecision()) / pool.totalDeposits();
            uint256 accountBorrowWeight = (pool.accountDebtAmount(account) *
                accruedRewardsPrecision()) / pool.totalLoans();

            console.log("supply=%s", accountSupplyWeight * totalSupplyRewards);
            console.log("borrow=%s", accountBorrowWeight * totalBorrowRewards);

            data.accruedRewards[reward] +=
                accountSupplyWeight *
                totalSupplyRewards +
                accountBorrowWeight *
                totalBorrowRewards;
            data.lastUpdate = block.timestamp;
        }
    }

    /**
     * @notice Claim reward
     * @dev Caller needs to pass which pools to calculate newAccrued rewards for
     * @param reward - the reward to claim
     * @param pools - lost of pools for which to update the accrued rewards before claiming - normally all of them
     */
    function claimForPools(IERC20 reward, address[] memory pools) public {
        address account = _msgSender();

        for (uint256 i = 0; i < pools.length; i++) {
            updateAccountRewards(account, pools[i]);
        }

        uint256 balance = _accountsData[account].accruedRewards[reward] /
            accruedRewardsPrecision();
        _accountsData[account].accruedRewards[reward] = 0;
        reward.safeTransferFrom(_rewardHolders[reward], account, balance);

        emit Claim(account, balance);
    }

    // ---------ADMIN METHODS

    /**
     * @notice Remember to notify users in advance and
     * allow them enough time to update their accrued rewards balances
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
