// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "../../flashloan/interfaces/IERC3156FlashBorrower.sol";
import "../../flashloan/interfaces/IERC3156FlashLender.sol";

import "../../libraries/DataTypesLib.sol";

import "../../IOwnable.sol";

interface IEntryPoint is IERC3156FlashLender, IERC3156FlashBorrower, IOwnable {
    function setCollateral(address asset, bool isCollateral) external;

    function increaseBorrowAllowance(
        address asset,
        address beneficiary,
        uint256 amount
    ) external;

    function increaseWithdrawAllowance(
        address asset,
        address beneficiary,
        uint256 amount
    ) external;

    function deposit(address asset, uint256 amount) external returns (uint256);

    function depositBehalf(
        address beneficiary,
        address asset,
        uint256 amount
    ) external returns (uint256);

    function borrow(address asset, uint256 amount) external returns (uint256);

    function repay(address asset, uint256 amount) external returns (uint256);

    function withdraw(address asset, uint256 amount) external returns (uint256);

    function liquidate(DataTypes.LiquidationCallVars calldata callVars)
        external;

    function flashLoan(DataTypes.FlashloanCallData memory vars)
        external
        returns (bool);
}
