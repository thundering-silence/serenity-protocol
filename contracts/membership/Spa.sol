// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "hardhat/console.sol";

import "../staking/interfaces/IZenGarden.sol";
import "../libraries/DataTypesLib.sol";

/**
 * @title Spa
 * @notice the Spa is a place where you can rest your BODY and relax.
 * SOUL is the receipt token for locking up BODY.
 * SOUL is non transferable
 */
contract Spa is ERC20("Soul", "SOUL"), Ownable {
    IZenGarden internal _zenGarden;
    address internal _treasury;
    uint256 internal _minLockAmount;
    mapping(DataTypes.Tier => DataTypes.TierConfig) internal _tiers;

    struct MemberData {
        DataTypes.Tier tier;
        uint256 unlockTime;
        uint256 depositedAmount;
    }
    mapping(address => DataTypes.MemberData) internal _members;

    event Join(address indexed account, uint256 unlockTime);
    event Deposit(address indexed account, uint256 amount);
    event ProlongLock(address indexed account, uint256 newUnlockTime);
    event Withdraw(address indexed account, uint256 amount);

    event TierConfigUpdate(
        DataTypes.Tier tier,
        uint256 feeReduction,
        uint256 minLock,
        uint256 receiptRatio
    );
    event UpdateZenGarden(address value);
    event UpdateTreasury(address value);
    event UpdateMinLockAmount(uint256 value);

    constructor(
        IZenGarden zenGarden_,
        address treasury_,
        uint256 minLockAmount_
    ) {
        _zenGarden = zenGarden_;
        _treasury = treasury_;
        _minLockAmount = minLockAmount_;
    }

    /**
     * @notice Calculate withdrawal penalty based on time remining to unlock and membership tier
     * if the unlock period has been prolonged beyond the maximum minLockPeriod the fee will me the maximised
     * else the fee will be reduced linearly every second
     */
    function _withdrawalPenalty(
        uint256 amount,
        uint256 start,
        uint256 end,
        uint256 currentTime
    ) internal pure returns (uint256) {
        uint256 maxPenalty = (maxWithdrawalPenalty() * amount) / 1 ether;
        uint256 remaining = end - currentTime;
        uint256 lockTime = end - start;
        if (remaining >= lockTime) {
            return maxPenalty;
        }
        return (remaining * maxPenalty) / lockTime;
    }

    function maxWithdrawalPenalty() public pure returns (uint256) {
        return 5 * 1e17;
    }

    function zenGarden() public view returns (IZenGarden) {
        return _zenGarden;
    }

    function treasury() public view returns (address) {
        return _treasury;
    }

    function tierConfig(DataTypes.Tier tier_)
        public
        view
        returns (DataTypes.TierConfig memory)
    {
        return _tiers[tier_];
    }

    function accountData(address account)
        public
        view
        returns (DataTypes.MemberData memory)
    {
        return _members[account];
    }

    /**
     * @notice Join the Spa
     * @param amount - the amount to deposit
     * @param lockPeriod - te amount of seconds to stay in the Spa
     */
    function join(uint256 amount, uint256 lockPeriod) public {
        DataTypes.MemberData storage data = _members[_msgSender()];
        require(data.depositedAmount == 0, "ENTER: Not a new member");
        require(amount >= _minLockAmount, "ENTER: Amount too small");
        require(
            lockPeriod >= _tiers[DataTypes.Tier.Calm].minLockPeriod,
            "ENTER: Lock period too short"
        );

        DataTypes.Tier tier = DataTypes.Tier.Calm;
        if (lockPeriod >= _tiers[DataTypes.Tier.Serene].minLockPeriod) {
            tier = DataTypes.Tier.Serene;
        } else if (
            lockPeriod >= _tiers[DataTypes.Tier.Peaceful].minLockPeriod
        ) {
            tier = DataTypes.Tier.Peaceful;
        }

        data.tier = tier;
        data.unlockTime = block.timestamp + lockPeriod;
        data.depositedAmount = amount;

        _zenGarden.transferFrom(_msgSender(), address(this), amount);
        _mint(_msgSender(), amount * _tiers[data.tier].receiptRatio);

        emit Join(_msgSender(), data.unlockTime);
    }

    /**
     * @notice Prolong the time to stay in the Spa
     * @dev msg cender needs to already have joined the Spa
     * @param additionalTime - the amount of time to add to the lockPeriod
     */
    function prolongLock(uint256 additionalTime) public {
        DataTypes.MemberData storage data = _members[_msgSender()];
        require(data.depositedAmount != 0, "PROLONG LOCK: Not a member");

        uint256 newUnlockTime = data.unlockTime + additionalTime;
        uint256 lockPeriod = newUnlockTime - block.timestamp;

        DataTypes.Tier tier = DataTypes.Tier.Calm;
        if (lockPeriod >= _tiers[DataTypes.Tier.Serene].minLockPeriod) {
            tier = DataTypes.Tier.Serene;
        } else if (
            lockPeriod >= _tiers[DataTypes.Tier.Peaceful].minLockPeriod
        ) {
            tier = DataTypes.Tier.Peaceful;
        }

        uint256 expectedAmount = _tiers[tier].receiptRatio *
            data.depositedAmount;
        uint256 amountToMint = expectedAmount - balanceOf(_msgSender());

        data.tier = tier;
        data.unlockTime = newUnlockTime;
        _mint(_msgSender(), amountToMint);

        emit ProlongLock(_msgSender(), data.unlockTime);
    }

    /**
     * @notice Deposit additional BODY into Spa
     * @dev caller must have already joined the Spa
     * @param amount - the amount to deposit
     */
    function deposit(uint256 amount) public {
        DataTypes.MemberData storage data = _members[_msgSender()];
        require(data.depositedAmount >= 0, "DEPOSIT: Not yet a member");

        data.depositedAmount += amount;

        _zenGarden.transferFrom(_msgSender(), address(this), amount);
        _mint(_msgSender(), amount * _tiers[data.tier].receiptRatio);

        emit Deposit(_msgSender(), amount);
    }

    /**
     * @notice Withdraw BODY from the Spa
     * @dev Requires the timelock to have expired
     */
    function withdraw() public {
        DataTypes.MemberData storage data = _members[_msgSender()];
        require(
            data.unlockTime < block.timestamp,
            "WITHDRAW: TimeLock not expired"
        );
        data.depositedAmount = 0;
        data.unlockTime = 0;
        _burn(
            _msgSender(),
            data.depositedAmount * _tiers[data.tier].receiptRatio
        );
        _zenGarden.transfer(_msgSender(), data.depositedAmount);

        emit Withdraw(_msgSender(), data.depositedAmount);
    }

    /**
     * @notice Compute withdrawal penalty for caller
     * @return uint - Fee fro withdrawing now
     */
    function withdrawalPenalty() public view returns (uint256) {
        DataTypes.MemberData storage data = _members[_msgSender()];
        if (data.unlockTime <= block.timestamp) {
            return 0;
        } else {
            return
                _withdrawalPenalty(
                    data.depositedAmount,
                    data.unlockTime - _tiers[data.tier].minLockPeriod,
                    data.unlockTime,
                    block.timestamp
                );
        }
    }

    /**
     * @notice Force withdraw funds from Spa
     * @dev Requires time lock to NOT have expired yet
     */
    function forceWithdraw() public {
        DataTypes.MemberData storage data = _members[_msgSender()];
        require(
            data.unlockTime >= block.timestamp,
            "FORCE WITHDRAW: TimeLock has expired"
        );
        DataTypes.TierConfig storage tier = _tiers[data.tier];
        uint256 penalty = _withdrawalPenalty(
            data.depositedAmount,
            data.unlockTime - tier.minLockPeriod,
            data.unlockTime,
            block.timestamp
        );
        _burn(_msgSender(), data.depositedAmount * tier.receiptRatio);
        _zenGarden.transfer(_msgSender(), data.depositedAmount - penalty);

        data.depositedAmount = 0;
        data.unlockTime = 0;

        _zenGarden.transferDepositedAmount(_msgSender(), _treasury, penalty);
        _zenGarden.transfer(_treasury, penalty);
    }

    /**
     * @notice Calculate fee starting from basefee by looking at the tier the user belongs to
     * @param account - the account for which to calculate the fee
     * @param baseFee - the maximum fee payable
     * @return uint - the fee to pay
     */
    function calculateFee(address account, uint256 baseFee)
        external
        view
        returns (uint256)
    {
        DataTypes.MemberData storage data = _members[account];
        // tier defaults to 0 so need to check depositedAmount
        if (data.depositedAmount > 0) {
            DataTypes.TierConfig storage config = _tiers[data.tier];
            uint256 feePercentToPay = 1 ether - config.feeReductionPercent;
            return (baseFee * feePercentToPay) / 1 ether;
        } else {
            return baseFee;
        }
    }

    /**
     * @notice Calculate the liquidation threshold for the account
     * @param account - the account for which to calculate the threshold
     * @param baseCollateral - the base collateralFactor set on the pool
     * @param maxCollateral - the maximum collateralFactor set on the pool
     * @return uint - the liquidation threshold
     */
    function calculateLiquidationThreshold(
        address account,
        uint256 baseCollateral,
        uint256 maxCollateral
    ) external view returns (uint256) {
        DataTypes.MemberData storage data = _members[account];
        // tier defaults to 0 so need to check depositedAmount
        if (data.depositedAmount > 0) {
            DataTypes.TierConfig storage config = _tiers[data.tier];
            uint256 delta = maxCollateral - baseCollateral;
            uint256 extraProtection = (delta * config.feeReductionPercent) /
                1 ether;

            return baseCollateral + extraProtection;
        } else {
            return baseCollateral;
        }
    }

    // ADMIN METHODS
    function updateTierConfig(
        DataTypes.Tier tier_,
        DataTypes.TierConfig memory config
    ) public onlyOwner {
        _tiers[tier_] = config;
        emit TierConfigUpdate(
            tier_,
            config.feeReductionPercent,
            config.minLockPeriod,
            config.receiptRatio
        );
    }

    function updateZenGarden(address value) public onlyOwner {
        _zenGarden = IZenGarden(value);
        emit UpdateZenGarden(value);
    }

    function updateTreasury(address value) public onlyOwner {
        _treasury = value;
        emit UpdateTreasury(value);
    }

    function updateMinLockAmount(uint256 value) public onlyOwner {
        _minLockAmount = value;
        emit UpdateMinLockAmount(value);
    }

    // BAN TRANSFERS
    function allowance(address, address)
        public
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    function transfer(address, uint256) public pure override returns (bool) {
        return false;
    }

    function approve(address, uint256) public pure override returns (bool) {
        return false;
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        return false;
    }
}
