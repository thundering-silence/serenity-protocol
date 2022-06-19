// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "hardhat/console.sol";

import "../staking/interfaces/IZenGarden.sol";
// import "./Ticketing.sol";

import "../libraries/DataTypesLib.sol";

/**
 * @title Thermae
 * @notice the Thermae is a place where you can rest your BODY and relax.
 * SOUL is the receipt token for locking up BODY.
 * SOUL is non transferable and used for governance
 */
contract Thermae is ERC20("Soul", "SOUL"), Ownable {
    using SafeERC20 for IZenGarden;

    IZenGarden internal _zenGarden;
    address internal _treasury;

    mapping(address => DataTypes.MemberData) internal _members;

    event Join(address indexed account, uint256 rank);
    event Deposit(address indexed account, uint256 amount);
    event ProlongLock(address indexed account, uint256 newUnlockTime);
    event Withdraw(address indexed account, uint256 amount);

    event UpdateZenGarden(address value);
    event UpdateTreasury(address value);
    event UpdateMinLockAmount(uint256 value);

    constructor(IZenGarden zenGarden_, address treasury_) {
        _zenGarden = zenGarden_;
        _treasury = treasury_;
    }

    function _getMultiplier(uint256 lockPeriod)
        internal
        pure
        returns (uint256 multiplier)
    {
        (
            uint256[] memory periods,
            uint256[] memory multipliers
        ) = lockMulitpliers();
        multiplier;
        for (uint256 i = 3; i >= 0; --i) {
            if (lockPeriod >= periods[i]) {
                multiplier = multipliers[i];
                break;
            }
        }
    }

    function lockMulitpliers()
        public
        pure
        returns (uint256[] memory, uint256[] memory)
    {
        uint256[] memory lockPeriods = new uint256[](4);
        uint256[] memory multipliers = new uint256[](4);

        lockPeriods[0] = 90 days;
        multipliers[0] = 1;

        lockPeriods[1] = 365 days;
        multipliers[1] = 10;

        lockPeriods[2] = 2 * 365 days;
        multipliers[2] = 25;

        lockPeriods[3] = 4 * 365 days;
        multipliers[3] = 100;

        return (lockPeriods, multipliers);
    }

    function zenGarden() public view returns (IZenGarden) {
        return _zenGarden;
    }

    function treasury() public view returns (address) {
        return _treasury;
    }

    function accountData(address account)
        public
        view
        returns (DataTypes.MemberData memory)
    {
        return _members[account];
    }

    /**
     * @notice Join the Thermae
     * @param amount - the amount to deposit
     * @param lockPeriod - the amount of seconds to stay in the Thermae
     */
    function join(uint256 amount, uint256 lockPeriod) public {
        DataTypes.MemberData storage data = _members[_msgSender()];
        require(data.depositedAmount == 0, "Thermae: Already joined");
        require(lockPeriod >= 90 days, "Thermae: lock period too small");
        data.unlockTime = block.timestamp + lockPeriod;
        data.depositedAmount = amount;

        _zenGarden.safeTransferFrom(_msgSender(), address(this), amount);

        _mint(_msgSender(), (amount * _getMultiplier(lockPeriod) * lockPeriod));

        emit Join(_msgSender(), amount);
    }

    /**
     * @notice Prolong the time to stay in the Thermae
     * @dev sender needs to already have joined the Thermae
     * @param additionalTime - the amount of time to add to the lockPeriod
     */
    function prolongLock(uint256 additionalTime) public {
        DataTypes.MemberData storage data = _members[_msgSender()];
        require(data.depositedAmount != 0, "Thermae: Not a member");

        uint256 newUnlockTime = data.unlockTime + additionalTime;
        uint256 lockPeriod = newUnlockTime - block.timestamp;

        uint256 expectedAmount = (data.depositedAmount *
            _getMultiplier(lockPeriod) *
            lockPeriod);

        uint256 amountToMint = expectedAmount - balanceOf(_msgSender());
        data.unlockTime = newUnlockTime;
        _mint(_msgSender(), amountToMint);

        emit ProlongLock(_msgSender(), data.unlockTime);
    }

    /**
     * @notice Deposit additional BODY into Thermae
     * @dev caller must have already joined the Thermae
     * @param amount - the amount to deposit
     */
    function deposit(uint256 amount) public {
        DataTypes.MemberData storage data = _members[_msgSender()];
        require(data.depositedAmount >= 0, "Thermae: Not a member");

        uint256 newDepositedAmount = data.depositedAmount + amount;
        uint256 lockPeriod = data.unlockTime - block.timestamp;

        // if remaining lock is less than allowed prolong to minimum allowed
        if (lockPeriod < 90 days) {
            lockPeriod = 90 days;
            data.unlockTime = block.timestamp + lockPeriod;
        }

        uint256 expectedAmount = (data.depositedAmount *
            _getMultiplier(lockPeriod) *
            lockPeriod);

        uint256 amountToMint = expectedAmount - balanceOf(_msgSender());
        data.depositedAmount = newDepositedAmount;

        _zenGarden.safeTransferFrom(_msgSender(), address(this), amount);
        _mint(_msgSender(), amountToMint);

        emit Deposit(_msgSender(), amount);
    }

    /**
     * @notice Withdraw BODY from the Thermae
     * @dev Requires the timelock to have expired
     */
    function withdraw() public {
        DataTypes.MemberData storage data = _members[_msgSender()];
        require(
            data.unlockTime < block.timestamp,
            "Thermae: TimeLock not expired"
        );
        uint256 amountToWithdraw = data.depositedAmount;
        data.depositedAmount = 0;
        data.unlockTime = 0;
        _burn(_msgSender(), balanceOf(_msgSender()));
        _zenGarden.safeTransfer(_msgSender(), amountToWithdraw);

        emit Withdraw(_msgSender(), amountToWithdraw);
    }

    /**
     * @notice Compute withdrawal penalty for caller
     * @return uint - Fee for withdrawing now
     */
    function withdrawalPenalty() public view returns (uint256) {
        DataTypes.MemberData storage data = _members[_msgSender()];
        if (data.unlockTime <= block.timestamp) {
            return 0;
        } else {
            return
                (data.depositedAmount * (data.unlockTime - block.timestamp)) /
                data.unlockTime;
        }
    }

    /**
     * @notice Force withdraw funds from Thermae
     * @dev Requires time lock to NOT have expired
     * the penalty for withdrawing early is sent to the treasury
     * which will then need to withdraw from ZenGarden and burn the MIND
     */
    function forceWithdraw() public {
        DataTypes.MemberData storage data = _members[_msgSender()];
        require(
            data.unlockTime >= block.timestamp,
            "Thermae: TimeLock has expired"
        );
        _burn(_msgSender(), balanceOf(_msgSender()));
        uint256 amountWithdrawn = data.depositedAmount;
        data.unlockTime = 0;
        data.depositedAmount = 0;

        uint256 penalty = withdrawalPenalty();
        _zenGarden.safeTransfer(_msgSender(), amountWithdrawn - penalty);
        // treasury will need to burn these tokens eventually
        _zenGarden.safeTransfer(_treasury, penalty);

        emit Withdraw(_msgSender(), amountWithdrawn);
    }

    // ADMIN METHOD
    function updateZenGarden(address value) public onlyOwner {
        _zenGarden = IZenGarden(value);
        emit UpdateZenGarden(value);
    }

    function updateTreasury(address value) public onlyOwner {
        _treasury = value;
        emit UpdateTreasury(value);
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
