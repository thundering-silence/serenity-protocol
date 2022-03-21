// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "../../libraries/DataTypesLib.sol";

import "../../IOwnable.sol";

interface IPoolStorage is IOwnable {
    function underlying() external view returns (address);

    function oracle() external view returns (address);

    function spa() external view returns (address);

    function feesCollector() external view returns (address);

    function rewardsManager() external view returns (address);

    function lendingConfig()
        external
        view
        returns (DataTypes.LendingConfig memory);

    function interestRateConfig()
        external
        view
        returns (DataTypes.InterestRateConfig memory);

    function flashLoanConfig()
        external
        view
        returns (DataTypes.FlashLoanConfig memory);

    function index() external view returns (uint256);

    function totalLoans() external view returns (uint256);

    function totalDeposits() external view returns (uint256);

    // ADMIN METHODS
    function updateOracle(address oracle_) external;

    function updateTreasuryAddress(address treasury_) external;

    function updateRewardsManager(address manager) external;

    function updateLendingConfig(DataTypes.LendingConfig memory lendingConfig_)
        external;

    function updateInterestRateConfig(
        DataTypes.InterestRateConfig memory interestRateConfig_
    ) external;

    function updateFlashLoanConfig(
        DataTypes.InterestRateConfig memory interestRateConfig_
    ) external;
}
