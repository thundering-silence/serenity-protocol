// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../main/interfaces/IEntryPoint.sol";


/**
* @notice Time Capsule contract - Lock funds  for a year and be among the first to receive MIND
* These funds will not be able to be used as collateral as being liquidated would allow to exit early
* The funds will be accruing rewards
*/
contract TimeCapsule is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable mind;
    uint public immutable dropAmount;
    
    IEntryPoint internal _entryPoint;
    uint256 internal _lockTime; // when to stop accepting deposits
    uint256 internal _unlockTime; // when are funds unlocked

    IERC20 public immutable _lockToken; // token to deposit
    mapping(address => uint256) internal _deposits; // map address to deposit amount
    uint internal _totalDeposited;

    event Join(address indexed account, uint256 amount);
    event Leave(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);

    constructor(
        IERC20 mind_,
        uint dropAmount_,
        IEntryPoint entryPoint_,
        IERC20 token_,
        uint256 lockTime_,
        uint256 lockLength
    ) {
        mind = mind_;
        dropAmount = dropAmount_;

        _entryPoint = entryPoint_;
        _lockTime = lockTime_;
        _unlockTime = block.timestamp + lockLength;
        _lockToken = token_;
    }

    modifier beforeLock() {
        require(block.timestamp <= _lockTime, "TimeCapsule: Locked");
        _;
    }

    modifier afterUnlock() {
        require(block.timestamp >= _unlockTime, "TimeCapsule: Locked");
        _;
    }

    function join(uint256 amount) public beforeLock {
        _lockToken.safeTransferFrom(_msgSender(), address(this), amount);
        _deposits[_msgSender()] += amount;
        _totalDeposited += amount;
        emit Join(_msgSender(), amount);
    }

    function leave(uint256 amount) public beforeLock {
        uint256 depositedAmount = _deposits[_msgSender()];
        uint256 actualAmount = amount > depositedAmount
            ? depositedAmount
            : amount;
        _totalDeposited -= actualAmount;
        _lockToken.safeTransfer(_msgSender(), actualAmount);
        emit Leave(_msgSender(), amount);
    }

    /**
     * @notice Deposit all locked funds to pool
     */
    function depositToPool() public {
        require(block.timestamp >= lockTime);
        require(block.timestamp <= _unlockTime);
        _entryPoint.deposit(address(_lockToken), _lockToken.balanceOf(address(this)));
    }

    // /**
    //  * @notice Withdraw funds from pool
    //  */
    // function withdrawFromPool(uint256 amount) public afterUnlock {
    //     _entryPoint.withdraw(address(_lockToken), amount);
    // }

    function claimRewards() public {

    }

    function withdraw() public afterUnlock {
        uint256 depositedAmount = _deposits[_msgSender()];
        _lockToken.safeTransfer(_msgSender(), depositedAmount);
        emit Withdraw(_msgSender(), depositedAmount);
    }

    function emergencyUnlock() public onlyOwner {
        _unlockTime = block.timestamp;
    }
}
