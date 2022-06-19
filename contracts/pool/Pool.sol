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
        address perksAggregator,
        address admin,
        DataTypes.LendingConfig memory lendingConfig,
        DataTypes.InterestRateConfig memory rateConfig,
        DataTypes.FlashLoanConfig memory flashConfig
    )
        PoolStorage(
            underlying,
            oracle,
            feesCollector,
            perksAggregator,
            admin,
            lendingConfig,
            rateConfig,
            flashConfig
        )
    {}

    /******HELPER METHODS */
    function _calculateAccruedInterest(
        uint256 prevIndex,
        uint256 currentIndex,
        uint256 multiplier
    ) internal pure returns (uint256 interest) {
        if (prevIndex != 0) {
            interest = (multiplier * (currentIndex - prevIndex)) / 1 ether;
        }
    }

    function _updateIndexes() internal {
        uint256 secondsElapsed = block.timestamp - _lastIndexUpdateTimestamp;

        uint256 rateForTimeElapsed = secondsElapsed != 0
            ? (borrowRate() * secondsElapsed) / 31557600 // seconds in julian year (365.25 days)
            : 0;

        _index = (_index * (1 ether + rateForTimeElapsed)) / 1 ether;

        uint256 fees = (rateForTimeElapsed * _lendingConfig.fee) / 1 ether;
        uint256 depositRateForTimeElapsed = (currentUtilisation() * fees) /
            1 ether;
        _depositIndex =
            (_depositIndex * (1 ether + depositRateForTimeElapsed)) /
            1 ether;
    }

    function _updateAccruedRewards() internal {
        if (address(_rewardsManager) != address(0)) {
            _rewardsManager.updatePoolRewardsData(address(this));
        }
    }

    function _setCollateral(address account, bool config) internal {
        _collaterals[account] = config;
    }

    /**
     * @notice internal deposit logic
     * @dev called in deposit() and depositBehalf()
     * @param account - the account for which the deposit is being made
     * @param amount - self explanatory
     * @param depositor - the origin of the funds
     * @return depositAmount - the total deposited amount for account
     */
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

    /**
     * @notice internal borrow logic
     * @dev called both in borrow() and borrowBehalf()
     * @param account - the account the loan will be opened for
     * @param amount - loan amount
     * @return borrowedAmount - total lent to account
     */
    function _borrow(address account, uint256 amount)
        internal
        returns (uint256 borrowedAmount)
    {
        require(_lendingConfig.allowBorrow, "Pool: borrowing is disabled");
        require(getCash() >= amount, "Pool: No more liquidity to borrow");
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

    /**
     * @notice internal logic for repaying a loan
     * @dev called both in repay() and repayBehalf()
     * @param account - the account for which to repay the loan
     * @param amount - amount to repay
     * @param repayer - the origin of the funds
     * @return leftoverDebt - the remaingin loan amount
     * @return actualAmount - the actual amount repayed (if amount was more than necessary)
     */
    function _repay(
        address account,
        uint256 amount,
        address repayer
    ) internal returns (uint256 leftoverDebt, uint256 actualAmount) {
        require(amount > 0, "Pool: Amount is 0");
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

    /**
     * @notice internal withdraw logic
     * @dev called in both withdraw() and withdrawBehalf()
     * @param account - the account for which funds are being withdrawn
     * @param amount - the amount to withdraw
     * @param recipient- the recipient of the withdrawn funds
     * @return leftoverDeposits - the remaining amount of deposits
     * @return actualAmount - the actual amount withdraw ("amount" arg could be more than actual deposits)
     */
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
        require(actualAmount <= getCash(), "Pool: Not enough liquidity");

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

    /****** PUBLIC METHODS */
    function underlyingPrice() public view returns (uint256) {
        return _oracle.getAssetPrice(address(_underlying));
    }

    // 100% = 1 ether
    function currentUtilisation() public view returns (uint256 utilisation) {
        if (_totalLoans == 0) {
            utilisation = 0;
        } else {
            utilisation = (_totalLoans * 1 ether) / _totalDeposits;
            require(
                utilisation <= 1 ether,
                "Pool: Utilisation rate beyond 100%"
            );
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
            uint256 b = 1 ether - _rateConfig.optimalUtilisation;
            uint256 c = (a * 1 ether) / b;
            rate =
                _rateConfig.baseRate +
                _rateConfig.slope1 +
                (c * _rateConfig.slope2) /
                1 ether;
        }
    }

    function getCash() public view returns (uint256) {
        return _underlying.balanceOf(address(this));
    }

    function isCollateral(address account) public view returns (bool) {
        return _collaterals[account];
    }

    /**
     * @notice the amount of collateral
     * @param account - the account for which to return the collateral amount
     */
    function accountCollateralAmount(address account)
        public
        view
        returns (uint256)
    {
        return isCollateral(account) ? accountDepositAmount(account) : 0;
    }

    /**
     * @notice the USD value of the collateral
     * @param account - the account for which to return the collateral value
     */
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
        return (accountDebtAmount(account) * underlyingPrice()) / 1 ether;
    }

    function accountDepositValue(address account)
        public
        view
        returns (uint256)
    {
        return (accountDepositAmount(account) * underlyingPrice()) / 1 ether;
    }

    function accountMaxDebtValue(address account, bool isLiquidating)
        public
        view
        returns (uint256 max)
    {
        max = 0;
        if (isCollateral(account)) {
            uint256 multiplier = _lendingConfig.collateralFactor;
            if (isLiquidating) {
                multiplier = _perksAggregator.calculateLiquidationThreshold(
                    account,
                    _lendingConfig.collateralFactor,
                    _lendingConfig.maxLiquidationThreshold
                );
            }
            uint256 amount = accountCollateralValue(account) * multiplier;
            max = amount / 1 ether;
        }
    }

    /** ENTRYPOINT ONLY METHODS **************/
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

    /**
     * @notice Increase borrow allowance of other address
     * @dev required for collateral and deposit swaps
     * @param account - the account granting allowance
     * @param beneficiary - the beneficiary of the allowance
     * @param amount - the amount to increase the allowance by
     */
    function increaseBorrowAllowance(
        address account,
        address beneficiary,
        uint256 amount
    ) public onlyRole(DELEGATOR_ROLE) {
        uint256 current = _borrowAllowances[account][beneficiary];
        uint256 maxIncrease = type(uint256).max - current;
        if (amount > maxIncrease) {
            amount = maxIncrease;
        }
        _borrowAllowances[account][beneficiary] += amount;
    }

    /**
     * @notice Increase withdrawal allowance of other address
     * @dev required for collateral and deposit swaps
     * @param account - the account granting allowance
     * @param beneficiary - the beneficiary of the allowance
     * @param amount - the amount to increase the allowance by
     */
    function increaseWithdrawAllowance(
        address account,
        address beneficiary,
        uint256 amount
    ) public onlyRole(DELEGATOR_ROLE) {
        uint256 current = _withdrawAllowances[account][beneficiary];
        uint256 maxIncrease = type(uint256).max - current;
        if (amount > maxIncrease) {
            amount = maxIncrease;
        }
        _withdrawAllowances[account][beneficiary] += amount;
    }

    /**
     * @notice allows to deposit on behalf of another account
     * @dev requires underlying allowance to be set prior to calling this
     * @param beneficiary - the account for which the deposit is being made for
     * @param amount - the amount to deposit
     * @param depositor - the origin of the funds
     */
    function depositBehalf(
        address beneficiary,
        uint256 amount,
        address depositor
    ) public onlyRole(DELEGATOR_ROLE) returns (uint256) {
        return _deposit(beneficiary, amount, depositor);
    }

    /**
     * @notice allows to deposit on behalf of another account
     * @dev requires borrow allowance to be set prior to calling this
     * @param account - the account for which the loan is being opened for
     * @param amount - the amount to borrow
     * @param initiator - the account triggering such action
     */
    function borrowBehalf(
        address account,
        uint256 amount,
        address initiator
    ) public onlyRole(DELEGATOR_ROLE) returns (uint256) {
        require(_borrowAllowances[account][initiator] >= amount);
        _borrowAllowances[account][initiator] -= amount;
        return _borrow(account, amount);
    }

    /**
     * @notice allows to withdraw on behalf of another account
     * @dev requires withdraw allowance to be set prior to calling this
     * @param account - the account for which the withdrawal is being made for
     * @param amount - the amount to withdraw
     * @param recipient - the recipient of funds and initiator of the withdrawal
     */
    function withdrawBehalf(
        address account,
        uint256 amount,
        address recipient
    ) public onlyRole(DELEGATOR_ROLE) returns (uint256, uint256) {
        require(_withdrawAllowances[account][recipient] >= amount);
        _withdrawAllowances[account][recipient] -= amount;
        return _withdraw(account, amount, recipient);
    }

    /**
     * @notice allows to repay on behalf of another account
     * @dev requires underlying allowance to be set prior to calling this
     * @param beneficiary - the account for which the deposit is being made for
     * @param amount - the amount to deposit
     * @param repayer - the origin of the funds
     */
    function repayBehalf(
        address beneficiary,
        uint256 amount,
        address repayer
    ) public onlyRole(DELEGATOR_ROLE) returns (uint256, uint256) {
        return _repay(beneficiary, amount, repayer);
    }

    /** FLASH LOAN METHODS ***************** */
    function maxFlashLoan() public view returns (uint256) {
        return _flashLoanConfig.active ? getCash() : 0;
    }

    function flashFee(address account, uint256 amount)
        public
        view
        returns (uint256)
    {
        require(amount >= 1 ether / _flashLoanConfig.fee);
        uint256 baseFee = (amount * _flashLoanConfig.fee) / 1 ether;
        return _perksAggregator.calculateFee(account, baseFee);
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

        require(
            receiver.onFlashLoan(
                _msgSender(),
                address(_underlying),
                amount,
                fee,
                data
            ) == keccak256("ERC3156FlashBorrower.onFlashLoan"),
            "Pool: flashloan callback failed"
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
