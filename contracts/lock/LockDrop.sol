// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../main/interfaces/IEntryPoint.sol";

contract TimeCapsule is Ownable {
    using SafeERC20 for IERC20;

    IEntryPoint internal _entryPoint;
    uint256 public immutable lockTime; // when to stop accepting deposits
    uint256 internal _unlockTime; // when are funds unlocked
    IERC20 public immutable _token; // token
    mapping(address => uint256) internal _deposits; // map address to deposit amount

    event Join(address indexed account, uint256 amount);
    event Leave(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);

    constructor(
        IEntryPoint entryPoint_,
        IERC20 token_,
        uint256 lockTime_,
        uint256 lockLength
    ) {
        _entryPoint = entryPoint_;
        lockTime = lockTime_;
        _unlockTime = block.timestamp + lockLength;
        _token = token_;
    }

    modifier beforeLock() {
        require(block.timestamp <= lockTime, "TimeCapsule: Locked");
        _;
    }

    modifier afterUnlock() {
        require(block.timestamp >= _unlockTime, "TimeCapsule: Locked");
        _;
    }

    function join(uint256 amount) public beforeLock {
        _token.safeTransferFrom(_msgSender(), address(this), amount);
        _deposits[_msgSender()] += amount;
        emit Join(_msgSender(), amount);
    }

    function leave(uint256 amount) public beforeLock {
        uint256 depositedAmount = _deposits[_msgSender()];
        uint256 actualAmount = amount > depositedAmount
            ? depositedAmount
            : amount;
        _token.safeTransfer(_msgSender(), actualAmount);
        emit Leave(_msgSender(), amount);
    }

    function depositToPool() public {
        require(block.timestamp >= lockTime);
        require(block.timestamp <= _unlockTime);
        _entryPoint.deposit(address(_token), _token.balanceOf(address(this)));
    }

    function withdrawFromPool(uint256 amount) public {
        require(block.timestamp >= _unlockTime);
        _entryPoint.withdraw(address(_token), amount);
    }

    function withdraw() public afterUnlock {
        uint256 depositedAmount = _deposits[_msgSender()];
        _token.safeTransfer(_msgSender(), depositedAmount);
        emit Withdraw(_msgSender(), depositedAmount);
    }

    function emergencyUnlock() public onlyOwner {
        _unlockTime = block.timestamp;
    }
}
