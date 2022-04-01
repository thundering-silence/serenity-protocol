// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title ZenGarden
 * @notice Zen Garden is the best place to rest your MIND. Deposit MIND and earn rewards.
 * BODY is a recipt token and is what entitles accounts to receive rewards.
 */
contract ZenGarden is ERC20("Body", "BODY"), Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    IERC20 internal _mind;
    address internal _thermae;

    EnumerableSet.AddressSet internal _rewards;
    mapping(address => bool) internal _pausedRewards;

    struct AccountData {
        // keep track of deposited MIND to allow safeTransfering BODY to Thermae contract and keep receiving rewards
        uint256 depositedAmount;
        mapping(IERC20 => uint256) lastClaimedRewardPerShare;
    }

    mapping(address => AccountData) internal _accountData;

    mapping(IERC20 => uint256) internal _rewardPerShare;

    event Enter(address indexed account, uint256 amount);
    event Exit(address indexed account, uint256 amount);
    event Deposit(address indexed reward, uint256 amount);
    event Claim(
        address indexed account,
        address indexed reward,
        uint256 amount
    );

    event ThermaeUpdate(address spa);
    event RewardActivated(address indexed reward);
    event RewardRemoved(address indexed reward);
    event RewardPaused(address indexed reward);
    event RewardUnpaused(address indexed reward);

    modifier onlyUnpaused(address reward) {
        require(_pausedRewards[reward] == false, "REWARD is PAUSED");
        _;
    }

    constructor(IERC20 mind_) {
        _mind = mind_;
    }

    function _increaseAmount(address account, uint256 amount) internal {
        _multiClaimFor(account, rewards());
        AccountData storage toData = _accountData[account];
        toData.depositedAmount += amount;
        emit Enter(account, amount);
    }

    function _decreaseAmount(address account, uint256 amount) internal {
        _multiClaimFor(account, rewards());
        AccountData storage fromData = _accountData[account];
        fromData.depositedAmount -= amount;
        emit Exit(account, amount);
    }

    function _claimableAmountFor(
        uint256 depositedAmount_,
        uint256 lastClaimedRewardPerShare,
        uint256 currentRewardPerShare
    ) internal pure returns (uint256) {
        if (
            lastClaimedRewardPerShare == currentRewardPerShare ||
            currentRewardPerShare == 0
        ) {
            return 0;
        } else {
            uint256 delta = currentRewardPerShare - lastClaimedRewardPerShare;
            uint256 claimableMult = delta * depositedAmount_;
            uint256 precision = rewardPerSharePrecision();
            return claimableMult >= precision ? claimableMult / precision : 0;
        }
    }

    function _claimFor(address account, IERC20 reward) internal {
        if (account != address(0)) {
            AccountData storage accountData = _accountData[account];
            uint256 current = _rewardPerShare[reward];
            uint256 amount = _claimableAmountFor(
                accountData.depositedAmount,
                accountData.lastClaimedRewardPerShare[reward],
                current
            );
            accountData.lastClaimedRewardPerShare[reward] = current;
            if (amount > 0) {
                reward.safeTransfer(account, amount);
                emit Claim(account, address(reward), amount);
            }
        }
    }

    function _multiClaimFor(address account, address[] memory rewardAddresses)
        internal
    {
        uint256 length = rewardAddresses.length;
        for (uint256 i = 0; i < length; i++) {
            _claimFor(account, IERC20(rewardAddresses[i]));
        }
    }

    function rewardPerSharePrecision() public pure returns (uint256) {
        return 1e27;
    }

    function mind() public view returns (IERC20) {
        return _mind;
    }

    function rewards() public view returns (address[] memory) {
        return _rewards.values();
    }

    function spa() public view returns (address) {
        return _thermae;
    }

    /**
     * @notice Deposit tokens for stakers to withdraw
     * @dev requires allowance to be set first
     * @param reward - the reward to pull
     * @param amount - the amount to pull
     */
    function depositReward(IERC20 reward, uint256 amount)
        public
        onlyUnpaused(address(reward))
    {
        require(_rewards.contains(address(reward)), "Unsupported Reward");
        reward.safeTransferFrom(_msgSender(), address(this), amount);
        uint256 rewardForOne = (amount * rewardPerSharePrecision()) /
            totalSupply();

        _rewardPerShare[reward] += rewardForOne;

        emit Deposit(address(reward), amount);
    }

    /**
     * @notice Enter Zen Garden
     * @dev pulls MIND & mints BODY
     * @param amount - the amount od MIND to pull
     */
    function enter(uint256 amount) public {
        address account = _msgSender();
        _increaseAmount(account, amount);
        _mint(account, amount);
        _mind.safeTransferFrom(account, address(this), amount);
    }

    /**
     * @notice Exit Zen Garden
     * @dev burns BODY & safeTransfers MIND
     * @param amount - the amount of BODY to burn
     */
    function exit(uint256 amount) public {
        address account = _msgSender();
        require(balanceOf(account) >= amount, "EXIT: Amount too big");
        _decreaseAmount(account, amount);
        _burn(account, amount);
        _mind.safeTransfer(account, amount);
    }

    /**
     * @notice Compute claimable amount of reward
     * @param reward - the reward (token) of which to calculate claimable amount
     */
    function claimableAmount(IERC20 reward) public view returns (uint256) {
        AccountData storage accountData = _accountData[_msgSender()];
        uint256 current = _rewardPerShare[reward];
        return
            _claimableAmountFor(
                accountData.depositedAmount,
                accountData.lastClaimedRewardPerShare[reward],
                current
            );
    }

    /**
     * @notice Claim signle reward
     * @param reward - the reward to claim
     */
    function claim(IERC20 reward) public {
        _claimFor(_msgSender(), reward);
    }

    /**
     * @notice claim multiple rewards at once
     * @param rewardAddresses - array of ERC20 compatible contract addresses
     */
    function multiClaim(address[] memory rewardAddresses) public {
        _multiClaimFor(_msgSender(), rewardAddresses);
    }

    function depositedAmount(address account) public view returns (uint256) {
        return _accountData[account].depositedAmount;
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {safeTransfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        // if locking into or releasing from Thermae do not update deposited amounts
        if (recipient != _thermae && sender != _thermae) {
            _decreaseAmount(sender, amount);
            _increaseAmount(recipient, amount);
        }
        super._transfer(sender, recipient, amount);
    }

    /**
     * @notice Reduce the deposited amount of from and increase deposited amount of to
     * this function is necessary to allow the treasury to accumulate rewards when users withdraw early from Thermae
     * @dev this function can only be called from Thermae on early withdrawal
     */
    function transferDepositedAmount(
        address from,
        address to,
        uint256 amount
    ) public {
        require(
            _msgSender() == _thermae,
            "Only Thermae contract can invoke such funtion"
        );
        _decreaseAmount(from, amount);
        _increaseAmount(to, amount);
    }

    // ADMIN METHODS
    function updateThermae(address spa_) public onlyOwner {
        _thermae = spa_;
        emit ThermaeUpdate(spa_);
    }

    function addReward(address token) public onlyOwner {
        _rewards.add(token);
        emit RewardActivated(token);
    }

    /**
     * @notice Ban deposits of such reward
     */
    function pauseReward(address reward) public onlyOwner {
        _pausedRewards[reward] = true;
        emit RewardPaused(reward);
    }

    function unpauseReward(address reward) public onlyOwner {
        _pausedRewards[reward] = false;
        emit RewardUnpaused(reward);
    }

    /**
     * @notice Remove reward from list of rewards, this will have the following effects:
     * enter & exit will no longer claim such token
     * the rewardPerShare will be rest to 0
     * @dev be sure to give enough notice to users
     */
    function removeReward(address reward) public onlyOwner {
        _rewards.remove(reward);
        _rewardPerShare[IERC20(reward)] = 0;
        emit RewardRemoved(reward);
    }
}
