// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "./IPoolStorage.sol";
import "../../flashloan/interfaces/IERC3156FlashBorrower.sol";

interface IPool is IPoolStorage {
    function underlyingPrice() external view returns (uint256);

    function currentUtilisation() external view returns (uint256);

    function borrowRate() external view returns (uint256);

    function getCash() external view returns (uint256);

    function isCollateral(address account) external view returns (bool);

    function accountCollateralAmount(address account)
        external
        view
        returns (uint256);

    function accountDepositAmount(address account)
        external
        view
        returns (uint256);

    function accountDebtAmount(address account) external view returns (uint256);

    function accountDebtValue(address account) external view returns (uint256);

    function accountMaxDebtValue(address account, bool isLiquidating)
        external
        view
        returns (uint256);

    function accountDepositValue(address account)
        external
        view
        returns (uint256);

    function accountCollateralValue(address account)
        external
        view
        returns (uint256);

    function setCollateral(address account, bool config) external;

    function deposit(address account, uint256 amount)
        external
        returns (uint256);

    function withdraw(address account, uint256 amount)
        external
        returns (uint256, uint256);

    function borrow(address account, uint256 amount) external returns (uint256);

    function repay(address account, uint256 amount)
        external
        returns (uint256, uint256);

    function increaseBorrowAllowance(address account, address beneficiary, uint256 amount)
        external;

    function increaseWithdrawAllowance(address account, address beneficiary, uint256 amount)
        external;

    function depositBehalf(
        address account,
        uint256 amount,
        address depositor
    ) external returns (uint256);

    function borrowBehalf(
        address account,
        uint256 amount,
        address receiver
    ) external returns (uint256);

    function repayBehalf(
        address account,
        uint256 amount,
        address repayer
    ) external returns (uint256, uint256);

    function withdrawBehalf(
        address account,
        uint256 amount,
        address receiver
    ) external;

    function maxFlashLoan() external view returns (uint256);

    function flashFee(address account, uint256 amount)
        external
        view
        returns (uint256);

    function flashLoan(
        IERC3156FlashBorrower borrower,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);
}
