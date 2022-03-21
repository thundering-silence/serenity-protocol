// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "../../integrations/swaps/interfaces/ISwapper.sol";
import "../../libraries/DataTypesLib.sol";
import "../../oracle/interfaces/IPriceOracle.sol";
import "../../pool/interfaces/IPool.sol";

import "../../IOwnable.sol";

interface IEntryPointStorage is IOwnable {
    function oracle() external view returns (IPriceOracle);

    function poolForUnderlying(address asset) external view returns (IPool);

    function supportedAssets() external view returns (address[] memory);

    function isAccountInMarket(address account, address poolAddress)
        external
        view
        returns (bool);

    function toggleMarketForAccount(address account, IPool pool) external;

    function accountMarkets(address account)
        external
        view
        returns (IPool[] memory);

    function accountOverallPosition(address account, bool isLiquidating)
        external
        view
        returns (
            uint256,
            uint256,
            bool
        );

    function accountCollateralValue(address account)
        external
        view
        returns (uint256);

    // ADMIN METHODS
    function supportNewAsset(address asset) external;

    function removeSupportForAsset(uint256 assetIndex) external;

    function createPool(
        address underlying,
        address feesCollector,
        DataTypes.LendingConfig memory lendingConfig,
        DataTypes.InterestRateConfig memory rateConfig,
        DataTypes.FlashLoanConfig memory flashConfig
    ) external returns (address poolAddress);

    function setPoolForUnderlying(address asset, address poolAddress) external;
}
