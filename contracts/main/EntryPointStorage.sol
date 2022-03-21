// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../integrations/swaps/interfaces/ISwapper.sol";

import "../libraries/DataTypesLib.sol";
import "../oracle/interfaces/IPriceOracle.sol";
import "../pool/interfaces/IPool.sol";
import "../pool/Pool.sol";

contract EntryPointStorage is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    ISpa internal _spa;
    IPriceOracle internal _oracle;

    EnumerableSet.AddressSet internal _supportedAssets;
    mapping(address => IPool) internal _poolForUnderlying;
    mapping(address => EnumerableSet.AddressSet) internal _userMarkets;

    event EnterMarket(address indexed account, address indexed market);
    event ExitMarket(address indexed account, address indexed market);
    event SupportedAssetUpdate(address indexed asset, bool isSupported);
    event NewPool(address indexed underlying, address indexed pool);
    event PoolForUnderlying(address indexed underlying, address indexed pool);

    constructor(address spa_, address oracle_) {
        _spa = ISpa(spa_);
        _oracle = IPriceOracle(oracle_);
    }

    // STORAGE VIEW METHODS
    function oracle() public view returns (IPriceOracle) {
        return _oracle;
    }

    function poolForUnderlying(address asset_) public view returns (IPool) {
        return _poolForUnderlying[asset_];
    }

    function supportedAssets() public view returns (address[] memory) {
        return _supportedAssets.values();
    }

    // ACCOUNT RELATED METHODS
    function _enterMarket(address account, address poolAddress) internal {
        if (!_userMarkets[account].contains(poolAddress)) {
            _userMarkets[account].add(poolAddress);
            emit EnterMarket(account, poolAddress);
        }
    }

    function _exitMarket(address account, address poolAddress) internal {
        if (_userMarkets[account].contains(poolAddress)) {
            _userMarkets[account].remove(poolAddress);
            emit ExitMarket(account, poolAddress);
        }
    }

    function isAccountInMarket(address account, address poolAddress)
        public
        view
        returns (bool)
    {
        return _userMarkets[account].contains(poolAddress);
    }

    function toggleMarketForAccount(address account, IPool pool) public {
        uint256 deposits = pool.accountDepositAmount(account);
        uint256 loans = pool.accountDebtAmount(account);
        if (isAccountInMarket(account, address(pool))) {
            if (deposits == 0 && loans == 0) {
                _exitMarket(account, address(pool));
            }
        } else {
            if (deposits != 0 || loans != 0) {
                _enterMarket(account, address(pool));
            }
        }
    }

    function accountMarkets(address account)
        public
        view
        returns (IPool[] memory)
    {
        address[] memory poolAddresses = _userMarkets[account].values();
        uint256 len = _userMarkets[account].length();
        IPool[] memory pools = new IPool[](len);
        for (uint256 i = 0; i < len; i++) {
            IPool pool = IPool(poolAddresses[i]);
            pools[i] = pool;
        }
        return pools;
    }

    function accountOverallPosition(address account, bool isLiquidating)
        public
        view
        returns (
            uint256 debtValue,
            uint256 maxDebtValue,
            bool shouldLiquidate
        )
    {
        IPool[] memory userPools = accountMarkets(account);
        uint256 length = userPools.length;
        for (uint8 i = 0; i < length; i++) {
            IPool pool = userPools[i];
            debtValue += pool.accountDebtValue(account);
            maxDebtValue += pool.accountMaxDebtValue(account, isLiquidating);
        }
        shouldLiquidate = debtValue > maxDebtValue;
    }

    function accountCollateralValue(address account)
        public
        view
        returns (uint256 collateralValue)
    {
        IPool[] memory userPools = accountMarkets(account);
        uint256 length = userPools.length;
        for (uint8 i = 0; i < length; i++) {
            IPool pool = userPools[i];
            if (address(pool) != address(0)) {
                collateralValue += pool.accountCollateralValue(account);
            }
        }
    }

    /***** ADMIN METHODS */
    function supportNewAsset(address asset) public onlyOwner {
        _supportedAssets.add(asset);
        emit SupportedAssetUpdate(asset, true);
    }

    function removeSupportForAsset(address asset) public onlyOwner {
        _supportedAssets.remove(asset);
        emit SupportedAssetUpdate(asset, false);
    }

    function createPool(
        address underlying,
        address feesCollector,
        DataTypes.LendingConfig memory lendingConfig,
        DataTypes.InterestRateConfig memory rateConfig,
        DataTypes.FlashLoanConfig memory flashConfig
    ) public onlyOwner returns (address poolAddress) {
        Pool pool = new Pool(
            underlying,
            address(_oracle),
            feesCollector,
            address(_spa),
            owner(),
            lendingConfig,
            rateConfig,
            flashConfig
        );
        poolAddress = address(pool);
        emit NewPool(underlying, poolAddress);
    }

    function setPoolForUnderlying(address asset, address pool)
        public
        onlyOwner
    {
        _poolForUnderlying[asset] = IPool(pool);
        emit PoolForUnderlying(asset, pool);
    }
}
