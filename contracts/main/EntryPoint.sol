// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../integrations/swaps/interfaces/ISwapper.sol";
import "../flashloan/interfaces/IERC3156FlashBorrower.sol";
import "../libraries/DataTypesLib.sol";
import "../oracle/interfaces/IPriceOracle.sol";
import "../pool/interfaces/IPool.sol";
import "../pool/Pool.sol";

import "./interfaces/IEntryPointStorage.sol";

import "hardhat/console.sol";

contract EntryPoint is IERC3156FlashBorrower, Ownable {
    using SafeERC20 for IERC20;

    IEntryPointStorage internal _storage;
    ISwapper internal _swapper;

    event Deposit(
        address indexed account,
        address indexed underlying,
        uint256 amount,
        address indexed initiator
    );
    event Withdraw(
        address indexed account,
        address indexed underlying,
        uint256 amount,
        address indexed receiver
    );
    event Borrow(
        address indexed account,
        address indexed underlying,
        uint256 amount,
        address indexed receiver
    );
    event Repay(
        address indexed account,
        address indexed underlying,
        uint256 amount,
        address indexed initiator
    );
    event Liquidation(
        address indexed account,
        address indexed debt,
        uint256 debtAmount,
        address indexed collateral,
        uint256 collateralAmount,
        address recipient
    );
    event DepositSwap(
        address indexed account,
        address indexed newCollateralAsset,
        uint256 newCollateral,
        address indexed toAsset,
        uint256 toAmount
    );
    event DebtSwap(
        address indexed account,
        address indexed fromAsset,
        uint256 fromAmount,
        address indexed toAsset,
        uint256 toAmount
    );
    event RepayWithCollateral(
        address indexed account,
        address indexed debtAsset,
        uint256 debtAmount,
        address indexed collateralAsset,
        uint256 collateralAmount
    );

    constructor(address storage_, address swapper_) {
        _storage = IEntryPointStorage(storage_);
        _swapper = ISwapper(swapper_);
    }

    /**
     * @notice Increase borrow allowance
     * @param asset the token to increase the allowance of
     * @param beneficiary the address that can borrow
     * @param amount the amount to increase the allowance by
     */
    function increaseBorrowAllowance(
        address asset,
        address beneficiary,
        uint256 amount
    ) public {
        _storage.poolForUnderlying(asset).increaseBorrowAllowance(
            _msgSender(),
            beneficiary,
            amount
        );
    }

    /**
     * @notice Increase withdraw allowance
     * @param asset the token to increase the allowance of
     * @param beneficiary the address that can borrow
     * @param amount the amount to increase the allowance by
     */
    function increaseWithdrawAllowance(
        address asset,
        address beneficiary,
        uint256 amount
    ) public {
        _storage.poolForUnderlying(asset).increaseWithdrawAllowance(
            _msgSender(),
            beneficiary,
            amount
        );
    }

    /**
     * @notice Set a deposits in pool as Collateral
     * @param asset the token to set as collateral
     * @param isCollateral configuration variable
     */
    function setCollateral(address asset, bool isCollateral) public {
        _storage.poolForUnderlying(asset).setCollateral(
            _msgSender(),
            isCollateral
        );
    }

    /**
     * @notice Deposit assets in the protocol
     * @param asset the token to deposit
     * @param amount the amount to deposit
     * @return depositAmount - the total deposit amount of underlying
     */
    function deposit(address asset, uint256 amount)
        public
        returns (uint256 depositAmount)
    {
        IPool pool = _storage.poolForUnderlying(asset);
        depositAmount = pool.deposit(_msgSender(), amount);
        _storage.toggleMarketForAccount(_msgSender(), pool);
        emit Deposit(_msgSender(), asset, amount, _msgSender());
    }

    /**
     * @notice Borrow assets from the protocol
     * @param asset the token to borrow
     * @param amount the amount to borrow
     * @return debtAmount - the total loan amount
     */
    function borrow(address asset, uint256 amount)
        public
        returns (uint256 debtAmount)
    {
        IPool pool = _storage.poolForUnderlying(asset);
        require(address(pool) != address(0), "Borrow: No Pool for asset");
        debtAmount = _storage.poolForUnderlying(asset).borrow(
            _msgSender(),
            amount
        );
        (, , bool shouldLiq) = _storage.accountOverallPosition(
            _msgSender(),
            false
        );
        require(shouldLiq == false, "Borrow: Liquidation threshold reached");

        _storage.toggleMarketForAccount(_msgSender(), pool);
        emit Borrow(_msgSender(), asset, amount, _msgSender());
    }

    /**
     * @notice Repay loan
     * @param asset the token to repay
     * @param amount the amount to repay
     * @return debtAmount - the leftover loan amount of asset
     */
    function repay(address asset, uint256 amount) public returns (uint256) {
        IPool pool = _storage.poolForUnderlying(asset);
        (uint256 debtAmount, uint256 actualAmount) = pool.repay(
            _msgSender(),
            amount
        );

        _storage.toggleMarketForAccount(_msgSender(), pool);
        emit Repay(_msgSender(), asset, actualAmount, _msgSender());

        return debtAmount;
    }

    /**
     * @notice Withdraw funds from protocol
     * @param asset the token to withdraw
     * @param amount the amount of token to withdraw
     * @return depositAmount - leftover deposit amount of asset
     */
    function withdraw(address asset, uint256 amount) public returns (uint256) {
        IPool pool = _storage.poolForUnderlying(asset);
        (uint256 depositAmount, uint256 actualAmount) = pool.withdraw(
            _msgSender(),
            amount
        );

        (, , bool shouldLiq) = _storage.accountOverallPosition(
            _msgSender(),
            false
        );
        require(shouldLiq == false, "Withdraw: Liquidation threshold reached");

        _storage.toggleMarketForAccount(_msgSender(), pool);
        emit Withdraw(_msgSender(), asset, actualAmount, _msgSender());

        return depositAmount;
    }

    /**
     * @notice Liquidate an account's position with specific amounts
     * @param callVars struct containing the information to execute the liquidation
     */
    function liquidate(DataTypes.LiquidationCallVars calldata callVars) public {
        {
            (, , bool shouldLiq) = _storage.accountOverallPosition(
                callVars.account,
                true
            );
            require(shouldLiq, "Liquidate: Account is not underwater");
        }

        DataTypes.LiquidationInternalVars memory vars;

        vars.debtAssetPool = _storage.poolForUnderlying(callVars.debtAsset);
        vars.collateralAssetPool = _storage.poolForUnderlying(
            callVars.collateralAsset
        );

        vars.debtAssetPrice = vars.debtAssetPool.underlyingPrice();
        vars.collateralAssetPrice = vars.collateralAssetPool.underlyingPrice();

        // Ensure collateral exists
        vars.collateralAmount = vars
            .collateralAssetPool
            .accountCollateralAmount(callVars.account);
        require(
            vars.collateralAmount > 0,
            "Liquidate: No available collateral"
        );

        uint256 accountDebtAmount = vars.debtAssetPool.accountDebtAmount(
            callVars.account
        );
        vars.debtAmount = callVars.debtAmount > accountDebtAmount
            ? accountDebtAmount
            : callVars.debtAmount;

        uint256 debtValue = callVars.debtAmount * vars.debtAssetPrice;

        // calculate fee
        DataTypes.FlashLoanConfig memory config = vars
            .collateralAssetPool
            .flashLoanConfig();
        vars.fee = config.fee;
        require(
            vars.debtAmount >= (1 ether / vars.fee),
            "Liquidate: Loan is too small"
        );
        // check above avoids logic below going to 0
        vars.feeValue = (vars.debtAmount * vars.fee) / 1 ether;

        vars.totalCollateralValue =
            (vars.collateralAmount * vars.collateralAssetPrice) /
            1 ether;
        vars.totalDebtValue = (debtValue + vars.feeValue);

        // define amount of collateral to release & amount to reduce debt by
        uint256 collateralToRelease;
        uint256 reduceDebtBy;
        {
            if (vars.totalCollateralValue >= vars.totalDebtValue) {
                collateralToRelease =
                    vars.totalDebtValue /
                    vars.collateralAssetPrice;
                reduceDebtBy = vars.debtAmount;
            } else {
                collateralToRelease = vars.collateralAmount;
                reduceDebtBy =
                    (vars.totalCollateralValue * (1 ether - vars.fee)) /
                    (vars.debtAssetPrice * 1 ether);
            }
        }

        // repay loan and transfer collateral
        vars.debtAssetPool.repayBehalf(
            callVars.account,
            vars.debtAmount,
            _msgSender()
        );
        vars.collateralAssetPool.withdrawBehalf(
            callVars.account,
            collateralToRelease,
            callVars.recipient
        );
        _storage.toggleMarketForAccount(callVars.account, vars.debtAssetPool);
        _storage.toggleMarketForAccount(
            callVars.account,
            vars.collateralAssetPool
        );

        emit Liquidation(
            callVars.account,
            callVars.debtAsset,
            vars.debtAmount,
            callVars.collateralAsset,
            collateralToRelease,
            callVars.recipient
        );
    }

    /**
     * @notice The fee to be charged for a given loan.
     * @param asset The loan currency.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address asset, uint256 amount)
        public
        view
        returns (uint256)
    {
        return _storage.poolForUnderlying(asset).flashFee(_msgSender(), amount);
    }

    /**
     * @notice The amount of currency available to be lent.
     * @param asset The loan currency.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address asset) public view returns (uint256) {
        return _storage.poolForUnderlying(asset).maxFlashLoan();
    }

    /**
     * @notice Top level function to trigger a flash loan - used for all flashloan related actions
     * @param vars struct containing data such as intent (default, collateralSwap, debtSwap), receiver, asset, amount etc.
     * @return true if everything went through successfully
     */
    function flashLoan(DataTypes.FlashloanCallData memory vars)
        public
        returns (bool)
    {
        require(vars.amount > 0, "FlashLoan: Amount must be more than 0");
        require(vars.intent < 4, "FlashLoan: Unrecognised intent");
        bytes memory data = abi.encode(
            vars.intent,
            vars.receiver,
            vars.asset,
            vars.amount,
            vars.account,
            vars.toAsset,
            vars.toAmount
        );
        console.log("asset=%s", vars.asset);
        return
            _storage.poolForUnderlying(vars.asset).flashLoan(
                vars.receiver,
                vars.amount,
                data
            );
    }

    /**
     * @notice flashLoan callback function - executes an action based on the passed variables
     * @param initiator original caller of flashLoan function
     * @param token asset borrowed
     * @param amount amount of token borrowed
     * @param fee flash loan fee
     * @param data bytes containing data such as intent (collateralSwap, debtSwap), receiver, asset, amount etc.
     * @return bytes required hash as per standard
     */
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(
            initiator == address(this),
            "FlashBorrower: Untrusted initiator"
        );
        DataTypes.FlashloanCallData memory vars;
        (
            vars.intent,
            vars.receiver,
            vars.asset,
            vars.amount,
            vars.account,
            vars.toAsset,
            vars.toAmount
        ) = abi.decode(
            data,
            (uint8, IERC3156FlashBorrower, address, uint256, address, address, uint256)
        );
        require(vars.intent != 0, "FlashBorrower: Wrong intent");
        require(
            vars.account != address(0),
            "FlashBorrower: Account is ZeroAddress"
        );
        console.log("asset=%s", vars.asset);
        console.log("token=%s", token);

        require(vars.asset == token, "FlashBorrower: Borrowed token mismatch");
        require(
            vars.amount == amount,
            "FlashBorrower: Borrowed amount mismatch"
        );

        if (vars.intent == 1) {
            depositSwap(vars.account, token, amount, vars.toAsset, fee);
        } else if (vars.intent == 2) {
            debtSwap(vars.account, token, amount, vars.toAsset, fee);
        } else if (vars.intent == 3) {
            repayWithCollateral(vars.account, token, amount, vars.toAsset, fee);
        }
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function depositSwap(
        address account,
        address newCollateralAsset,
        uint256 newCollateralAmount,
        address oldCollateralAsset,
        uint256 fee
    ) internal {
        IPool fromPool = _storage.poolForUnderlying(oldCollateralAsset);
        IPool toPool = _storage.poolForUnderlying(newCollateralAsset);
        IERC20 fromToken = IERC20(oldCollateralAsset);
        IERC20 toToken = IERC20(newCollateralAsset);
        console.log("before deposit behalf");
        // by now we have toAmount to toAsset
        toToken.safeIncreaseAllowance(address(toPool), newCollateralAmount);
        toPool.depositBehalf(account, newCollateralAmount, address(this));
        emit Deposit(
            account,
            newCollateralAsset,
            newCollateralAmount,
            address(this)
        );
        console.log("after deposit behalf");
        // set as collateral only if the original was set as collateral too
        if (fromPool.accountCollateralAmount(account) > 0) {
            toPool.setCollateral(account, true);
        }

        // withdraw all the deposited tokens - the swap remainder will be deposited back
        uint256 cash = fromPool.getCash();
        console.log("cash=%s", cash);
        fromPool.withdrawBehalf(account, cash, address(this));
        emit Withdraw(
            account,
            oldCollateralAsset,
            cash,
            address(this)
        );
        console.log("before swap");
        uint256 balanceBeforeSwap = fromToken.balanceOf(address(this));
        _swapper.swapTokensForExactTokens(
            oldCollateralAsset,
            fromToken.balanceOf(address(this)),
            newCollateralAsset,
            newCollateralAmount + fee,
            address(this),
            block.timestamp + 300
        );
        uint256 balanceAfterSwap = fromToken.balanceOf(address(this));

        // deposit the leftover after swapping
        fromPool.depositBehalf(account, balanceAfterSwap, address(this));
        emit Deposit(
            account,
            oldCollateralAsset,
            balanceAfterSwap,
            address(this)
        );

        (, , bool shouldLiq) = _storage.accountOverallPosition(
            _msgSender(),
            false
        );
        require(shouldLiq == false, "DepositSwap: Account would go underwater");

        // allow pool to pull tokens
        toToken.safeIncreaseAllowance(
            address(toPool),
            fee + newCollateralAmount
        );

        emit DepositSwap(
            account,
            oldCollateralAsset,
            balanceBeforeSwap - balanceAfterSwap,
            newCollateralAsset,
            newCollateralAmount
        );

        _storage.toggleMarketForAccount(account, fromPool);
        _storage.toggleMarketForAccount(account, toPool);
    }

    function debtSwap(
        address account,
        address oldDebtAsset,
        uint256 oldDebtAmount,
        address newDebtAsset,
        uint256 fee
    ) public {
        IPool fromPool = _storage.poolForUnderlying(oldDebtAsset);
        IPool toPool = _storage.poolForUnderlying(newDebtAsset);
        IERC20 fromToken = IERC20(oldDebtAsset);
        IERC20 toToken = IERC20(newDebtAsset);

        // by now we have oldDebtAmount of oldDebtAsset
        fromPool.repayBehalf(account, oldDebtAmount, address(this));
        emit Repay(account, oldDebtAsset, oldDebtAmount, address(this));

        // borrow all of available cash - the remainder from the swap will be deposited back
        uint256 poolCash = toPool.getCash();
        toPool.borrowBehalf(account, toPool.getCash(), address(this));
        emit Borrow(account, newDebtAsset, poolCash, address(this));

        uint256 balanceBeforeSwap = toToken.balanceOf(address(this));
        // swap to be able to repay flashloan
        _swapper.swapTokensForExactTokens(
            newDebtAsset,
            balanceBeforeSwap,
            oldDebtAsset,
            oldDebtAmount + fee,
            address(this),
            block.timestamp + 300
        );

        uint256 balanceAfterSwap = toToken.balanceOf(address(this));

        // repay the leftover from swap
        toPool.repayBehalf(account, balanceAfterSwap, address(this));
        emit Repay(account, newDebtAsset, balanceAfterSwap, address(this));

        (, , bool shouldLiq) = _storage.accountOverallPosition(account, false);
        require(shouldLiq == false, "DebtSwap: Account would go underwater");

        // allow pool to pull tokens
        fromToken.safeIncreaseAllowance(address(fromPool), fee + oldDebtAmount);

        emit DebtSwap(
            account,
            oldDebtAsset,
            oldDebtAmount,
            newDebtAsset,
            balanceBeforeSwap - balanceAfterSwap
        );

        _storage.toggleMarketForAccount(account, fromPool);
        _storage.toggleMarketForAccount(account, toPool);
    }

    function repayWithCollateral(
        address account,
        address debtAsset,
        uint256 debtAmount,
        address collateralAsset,
        uint256 fee
    ) public {
        IPool debtPool = _storage.poolForUnderlying(debtAsset);
        IPool collateralPool = _storage.poolForUnderlying(collateralAsset);
        IERC20 debtToken = IERC20(debtAsset);
        IERC20 collateralToken = IERC20(collateralAsset);

        // repay debt
        debtPool.repayBehalf(account, debtAmount, address(this));

        // withdraw enough to repay flash loan
        collateralPool.withdrawBehalf(
            account,
            collateralPool.accountCollateralAmount(account),
            address(this)
        );

        uint256 balanceBeforeSwap = collateralToken.balanceOf(address(this));

        _swapper.swapTokensForExactTokens(
            collateralAsset,
            balanceBeforeSwap,
            debtAsset,
            debtAmount + fee,
            address(this),
            block.timestamp + 300
        );

        uint256 balanceAfterSwap = collateralToken.balanceOf(address(this));

        // deposit leftover from swap
        collateralPool.repayBehalf(account, balanceAfterSwap, address(this));

        // allow pool to pull funds
        debtToken.safeIncreaseAllowance(address(debtPool), debtAmount + fee);

        emit RepayWithCollateral(
            account,
            debtAsset,
            debtAmount,
            collateralAsset,
            balanceBeforeSwap - balanceAfterSwap
        );

        _storage.toggleMarketForAccount(account, debtPool);
        _storage.toggleMarketForAccount(account, collateralPool);
    }
}
