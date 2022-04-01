// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./PoolStorage.sol";
import "../flashloan/interfaces/IERC3156FlashBorrower.sol";
import "../flashloan/interfaces/IERC3156FlashLender.sol";
import "../oracle/interfaces/IPriceOracle.sol";
import "../libraries/DataTypesLib.sol";

import "hardhat/console.sol";

contract Pool is PoolStorage {
    using SafeERC20 for IERC20;

    constructor(
        address underlying,
        address oracle,
        address feesCollector,
        address spa,
        address admin,
        DataTypes.LendingConfig memory lendingConfig,
        DataTypes.InterestRateConfig memory rateConfig,
        DataTypes.FlashLoanConfig memory flashConfig
    )
        PoolStorage(
            underlying,
            oracle,
            feesCollector,
            spa,
            admin,
            lendingConfig,
            rateConfig,
            flashConfig
        )
    {}

    /******HELPER METHODS */
    function one() public pure returns (uint256) {
        return 1 ether;
    }

    function _calculateAccruedInterest(
        uint256 prevIndex_,
        uint256 currentIndex_,
        uint256 multiplier_
    ) internal pure returns (uint256 interest) {
        if (prevIndex_ != 0) {
            interest = (multiplier_ * (currentIndex_ - prevIndex_)) / one();
        }
    }

    function _updateIndexes() internal {
        uint256 secondsElapsed = block.timestamp - _lastIndexUpdateTimestamp;

        uint256 rateForTimeElapsed = secondsElapsed != 0
            ? (borrowRate() * secondsElapsed) / 31557600 // seconds in julian year (365.25 days)
            : 0;

        _index = (_index * (one() + rateForTimeElapsed)) / one();

        uint256 nonTreasury = (rateForTimeElapsed * _lendingConfig.fee) / one();
        uint256 depositRateForTimeElapsed = (currentUtilisation() *
            nonTreasury) / one();
        _depositIndex =
            (_depositIndex * (one() + depositRateForTimeElapsed)) /
            one();
    }

    function _updateAccruedRewards() internal {
        if (address(_rewardsManager) != address(0)) {
            _rewardsManager.updatePoolRewardsData(address(this));
        }
    }

    function _setCollateral(address account, bool config) internal {
        _collaterals[account] = config;
    }

    function _deposit(
        address account,
        uint256 amount,
        address depositor
    ) internal returns (uint256 depositAmount) {
        _updateAccruedRewards();

        // update position
        Snapshot storage position = _deposits[account];
        uint256 accruedInterest = _calculateAccruedInterest(
            position.index,
            _depositIndex,
            position.amount
        );
        position.accruedInterest += accruedInterest;
        position.amount += amount;
        position.index = _depositIndex;
        depositAmount = position.amount + position.accruedInterest;

        // update total deposits
        _totalDeposits += amount;
        // safeTransfer
        _underlying.safeTransferFrom(depositor, address(this), amount);
        // update indexes
        _updateIndexes();
    }

    function _borrow(address account, uint256 amount)
        internal
        returns (uint256 borrowedAmount)
    {
        require(_lendingConfig.allowBorrow, "BORROW: borrowing is disabled");
        require(getCash() >= amount, "No more liquidity to borrow");
        _updateAccruedRewards();
        // update position
        Snapshot storage position = _debts[account];
        position.accruedInterest += _calculateAccruedInterest(
            position.index,
            _index,
            position.amount
        );
        position.index = _index;
        position.amount += amount;
        borrowedAmount = position.amount;

        // update total loans
        _totalLoans += amount;
        // safeTransfer
        _underlying.safeTransfer(account, amount);
        // update indexes
        _updateIndexes();
    }

    function _repay(
        address account,
        uint256 amount,
        address repayer
    ) internal returns (uint256 leftoverDebt, uint256 actualAmount) {
        require(amount > 0, "Amount is 0");
        _updateAccruedRewards();
        // update position
        Snapshot storage position = _debts[account];
        uint256 newInterest = _calculateAccruedInterest(
            position.index,
            _index,
            position.amount
        );
        position.accruedInterest += newInterest;
        position.index = _index;

        uint256 interestAmount = position.accruedInterest;
        uint256 totalDebt = interestAmount + position.amount;
        actualAmount = amount > totalDebt ? totalDebt : amount;

        // always repay interest first
        uint256 fees;
        uint256 removeFromLoans;
        if (actualAmount <= interestAmount) {
            fees = (actualAmount * _lendingConfig.fee) / 1 ether;
            position.accruedInterest -= actualAmount;
            removeFromLoans = 0;
        } else {
            fees = (interestAmount * _lendingConfig.fee) / 1 ether;
            position.accruedInterest = uint256(0);
            removeFromLoans = actualAmount - interestAmount;
            position.amount -= removeFromLoans;
        }

        leftoverDebt = totalDebt - actualAmount;

        // update total total loans
        _totalLoans -= removeFromLoans;
        // send fees to FeesCollector
        _underlying.safeTransferFrom(repayer, address(_feesCollector), fees);
        _feesCollector.updateAccumulatedAmount(address(this), fees);

        // repay the rest
        _underlying.safeTransferFrom(
            repayer,
            address(this),
            actualAmount - fees
        );
        // update indexes
        _updateIndexes();
    }

    function _withdraw(
        address account,
        uint256 amount,
        address recipient
    ) internal returns (uint256 leftoverDeposits, uint256 actualAmount) {
        _updateAccruedRewards();
        // update position
        Snapshot storage position = _deposits[account];
        position.accruedInterest += _calculateAccruedInterest(
            position.index,
            _depositIndex,
            position.amount
        );
        position.index = _depositIndex;

        uint256 totalDeposits = position.amount + position.accruedInterest;
        actualAmount = amount > totalDeposits ? totalDeposits : amount;
        require(actualAmount <= getCash(), "Not enough liquidity");

        // always withdraw interest first
        uint256 removeFromDeposits;
        if (actualAmount <= position.accruedInterest) {
            position.accruedInterest = position.accruedInterest - actualAmount;
            removeFromDeposits = 0;
        } else {
            uint256 extra = actualAmount - position.accruedInterest;
            position.accruedInterest = uint256(0);
            position.amount = position.amount - extra;
            removeFromDeposits = extra;
        }

        leftoverDeposits = position.amount + position.accruedInterest;

        // update total deposits
        _totalDeposits -= removeFromDeposits;
        // safeTransfer
        _underlying.safeTransfer(recipient, actualAmount);
        // update indexes
        _updateIndexes();
    }

    /****** MAIN METHODS */
    function underlyingPrice() public view returns (uint256) {
        return _oracle.getAssetPrice(address(_underlying));
    }

    // 100% = 1 ether
    function currentUtilisation() public view returns (uint256 utilisation) {
        if (_totalLoans == 0) {
            utilisation = 0;
        } else {
            utilisation = (_totalLoans * one()) / _totalDeposits;
            require(utilisation <= one(), "Utilisation rate beyond 100%");
        }
    }

    // 100% = 1 ether
    function borrowRate() public view returns (uint256 rate) {
        uint256 utilisation = currentUtilisation();
        if (utilisation <= _rateConfig.optimalUtilisation) {
            uint256 coefficient = (utilisation * _rateConfig.slope1) /
                _rateConfig.optimalUtilisation;
            rate = _rateConfig.baseRate + coefficient;
        } else {
            uint256 a = utilisation - _rateConfig.optimalUtilisation;
            uint256 b = uint256(one()) - _rateConfig.optimalUtilisation;
            uint256 c = (a * one()) / b;
            rate =
                _rateConfig.baseRate +
                _rateConfig.slope1 +
                (c * _rateConfig.slope2) /
                one();
        }
    }

    function getCash() public view returns (uint256) {
        return _underlying.balanceOf(address(this));
    }

    function isCollateral(address account) public view returns (bool) {
        return _collaterals[account];
    }

    function accountCollateralAmount(address account)
        public
        view
        returns (uint256)
    {
        return isCollateral(account) ? accountDepositAmount(account) : 0;
    }

    function accountCollateralValue(address account)
        public
        view
        returns (uint256)
    {
        return isCollateral(account) ? accountDepositValue(account) : 0;
    }

    function accountDepositAmount(address account)
        public
        view
        returns (uint256)
    {
        Snapshot storage position = _deposits[account];
        return
            position.amount > 0
                ? position.amount + position.accruedInterest
                : 0;
    }

    function accountDebtAmount(address account) public view returns (uint256) {
        Snapshot storage position = _debts[account];
        return
            position.amount > 0
                ? position.amount + position.accruedInterest
                : 0;
    }

    function accountDebtValue(address account) public view returns (uint256) {
        return (accountDebtAmount(account) * underlyingPrice()) / one();
    }

    function accountDepositValue(address account)
        public
        view
        returns (uint256)
    {
        return (accountDepositAmount(account) * underlyingPrice()) / one();
    }

    function accountMaxDebtValue(address account, bool isLiquidating)
        public
        view
        returns (uint256 price)
    {
        price = 0;
        if (isCollateral(account)) {
            uint256 multiplier = _lendingConfig.collateralFactor;
            if (isLiquidating) {
                multiplier = _thermae.calculateLiquidationThreshold(
                    account,
                    _lendingConfig.collateralFactor,
                    _lendingConfig.maxLiquidationThreshold
                );
            }
            uint256 amount = accountCollateralValue(account) * multiplier;
            price = amount / one();
        }
    }

    function setCollateral(address account, bool config)
        public
        onlyRole(DELEGATOR_ROLE)
    {
        _setCollateral(account, config);
    }

    function deposit(address account, uint256 amount)
        public
        onlyRole(DELEGATOR_ROLE)
        returns (uint256)
    {
        return _deposit(account, amount, account);
    }

    function withdraw(address account, uint256 amount)
        public
        onlyRole(DELEGATOR_ROLE)
        returns (uint256, uint256)
    {
        return _withdraw(account, amount, account);
    }

    function borrow(address account, uint256 amount)
        public
        onlyRole(DELEGATOR_ROLE)
        returns (uint256)
    {
        return _borrow(account, amount);
    }

    function repay(address account, uint256 amount)
        public
        onlyRole(DELEGATOR_ROLE)
        returns (uint256, uint256)
    {
        return _repay(account, amount, account);
    }

    function increaseBorrowAllowance(
        address account,
        address beneficiary,
        uint256 amount
    ) public onlyRole(DELEGATOR_ROLE) {
        uint256 current = _borrowAllowances[account][beneficiary];
        uint256 maxIncrease = (2**256 - 1) - current;
        if (amount > maxIncrease) {
            amount = maxIncrease;
        }
        _borrowAllowances[account][beneficiary] += amount;
    }

    function increaseWithdrawAllowance(
        address account,
        address beneficiary,
        uint256 amount
    ) public onlyRole(DELEGATOR_ROLE) {
        uint256 current = _withdrawAllowances[account][beneficiary];
        uint256 maxIncrease = (2**256 - 1) - current;
        if (amount > maxIncrease) {
            amount = maxIncrease;
        }
        _withdrawAllowances[account][beneficiary] += amount;
    }

    function depositBehalf(
        address beneficiary,
        uint256 amount,
        address depositor
    ) public onlyRole(DELEGATOR_ROLE) returns (uint256) {
        return _deposit(beneficiary, amount, depositor);
    }

    function borrowBehalf(
        address account,
        uint256 amount,
        address initiator
    ) public onlyRole(DELEGATOR_ROLE) returns (uint256) {
        require(_borrowAllowances[account][initiator] >= amount);
        _borrowAllowances[account][initiator] -= amount;
        return _borrow(account, amount);
    }

    function withdrawBehalf(
        address account,
        uint256 amount,
        address recipient
    ) public onlyRole(DELEGATOR_ROLE) returns (uint256, uint256) {
        require(_withdrawAllowances[account][recipient] >= amount);
        _withdrawAllowances[account][recipient] -= amount;
        return _withdraw(account, amount, recipient);
    }

    function repayBehalf(
        address beneficiary,
        uint256 amount,
        address repayer
    ) public onlyRole(DELEGATOR_ROLE) returns (uint256, uint256) {
        return _repay(beneficiary, amount, repayer);
    }

    /** FLASH LOAN***************** */
    function maxFlashLoan() public view returns (uint256) {
        return _flashLoanConfig.active ? getCash() : 0;
    }

    function flashFee(address account, uint256 amount)
        public
        view
        returns (uint256)
    {
        uint256 baseFee = ((amount * (1 ether + _flashLoanConfig.fee)) /
            1 ether) - amount;
        return _thermae.calculateFee(account, baseFee);
    }

    function flashLoan(
        IERC3156FlashBorrower receiver,
        uint256 amount,
        bytes calldata data
    ) external onlyRole(DELEGATOR_ROLE) returns (bool) {
        (, , , address account, , ) = abi.decode(
            data,
            (uint8, address, uint256, address, address, uint256)
        );
        uint256 fee = flashFee(account, amount);
        _underlying.safeTransfer(address(receiver), amount);

        console.log("underlying=%s", address(_underlying));
        require(
            receiver.onFlashLoan(
                _msgSender(),
                address(_underlying),
                amount,
                fee,
                data
            ) == keccak256("ERC3156FlashBorrower.onFlashLoan"),
            "FlashLender: Callback failed"
        );
        _underlying.safeTransferFrom(
            address(receiver),
            address(this),
            amount + fee
        );
        _underlying.safeTransfer(address(_feesCollector), fee);
        _feesCollector.updateAccumulatedAmount(address(this), fee);

        return true;
    }
}
