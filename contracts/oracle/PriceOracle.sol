// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../integrations/oracles/interfaces/IDexPriceOracle.sol";
import "../integrations/oracles/interfaces/IAggregatorV3.sol";

import "hardhat/console.sol";

contract PriceOracle is Ownable {
    using SafeMath for uint256;

    event AssetSourceUpdated(address indexed asset, address indexed source);
    event FallbackOracleUpdated(address indexed fallbackOracle);

    struct Source {
        IAggregatorV3 aggregator;
        bool returnsUSD;
    }

    mapping(address => Source) private _assetsSources;
    IDexPriceOracle private _fallbackOracle;
    address public immutable wNative;

    constructor(address wnative_) {
        wNative = wnative_;
    }

    function _setAssetsSources(
        address[] memory assets_,
        address[] memory aggregators_,
        bool[] memory confUSD_
    ) internal {
        uint256 assetsLength = assets_.length;
        uint256 aggregatorsLength = aggregators_.length;
        uint256 confUSDLength = confUSD_.length;
        require(
            assetsLength == aggregatorsLength && assetsLength == confUSDLength,
            "INCONSISTENT_PARAMS_LENGTH"
        );
        for (uint256 i = 0; i < assets_.length; i++) {
            setAssetSource(assets_[i], aggregators_[i], confUSD_[i]);
        }
    }

    function _setFallbackOracle(address fallbackOracle_) internal {
        require(fallbackOracle_ != address(0));
        _fallbackOracle = IDexPriceOracle(fallbackOracle_);
        emit FallbackOracleUpdated(fallbackOracle_);
    }

    function _fallbackOraclePrice(address asset_, uint256 nativePriceUSD)
        internal
        view
        returns (uint256 price)
    {
        (uint256 quote, bool inverted) = _fallbackOracle.getAssetPrice(
            asset_,
            wNative
        );
        price = inverted
            ? nativePriceUSD.div(quote)
            : nativePriceUSD.mul(quote);
    }

    /**
     * @notice get asset price denominated in USD
     * @param asset {address} - asset which price we want to retrieve
     * @return price {uint256}
     */
    function getAssetPrice(address asset) public view returns (uint256 price) {
        // USD prices return with 8 decimals, NATIVE prices with 18
        uint256 USDpriceMultiplier = 1e10;
        Source storage sourceNative = _assetsSources[wNative];
        require(
            sourceNative.returnsUSD == true,
            "NativeSource returns price in Native"
        );
        (, int256 priceUSD, , , ) = sourceNative.aggregator.latestRoundData();
        require(priceUSD > 0, "Native is worth $0");
        uint256 nativePriceUSD = uint256(priceUSD).mul(USDpriceMultiplier);

        if (asset == wNative) {
            price = nativePriceUSD;
        } else {
            Source storage source = _assetsSources[asset];
            if (address(source.aggregator) == address(0)) {
                price = _fallbackOraclePrice(asset, nativePriceUSD);
            } else {
                (, int256 answer, , , ) = source.aggregator.latestRoundData();
                if (answer > 0) {
                    price = source.returnsUSD
                        ? uint256(answer).mul(USDpriceMultiplier)
                        : uint256(answer).mul(nativePriceUSD);
                } else {
                    price = _fallbackOraclePrice(asset, nativePriceUSD);
                }
            }
        }
    }

    function getAssetsPrices(address[] calldata assets_)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory prices = new uint256[](assets_.length);
        for (uint256 i = 0; i < assets_.length; i++) {
            prices[i] = getAssetPrice(assets_[i]);
        }
        return prices;
    }

    function setFallbackOracle(address fallbackOracle_) public onlyOwner {
        _setFallbackOracle(fallbackOracle_);
    }

    function getFallbackOracle() public view returns (address) {
        return address(_fallbackOracle);
    }

    function setAssetSource(
        address asset_,
        address aggregator_,
        bool isUSD
    ) public onlyOwner {
        Source storage source = _assetsSources[asset_];
        source.aggregator = IAggregatorV3(aggregator_);
        source.returnsUSD = isUSD;

        emit AssetSourceUpdated(asset_, aggregator_);
    }

    function setAssetsSources(
        address[] calldata assets_,
        address[] calldata aggregators_,
        bool[] calldata confUSD_
    ) public onlyOwner {
        _setAssetsSources(assets_, aggregators_, confUSD_);
    }

    function getAssetSource(address asset_)
        public
        view
        returns (address aggr, bool isUSD)
    {
        Source storage source = _assetsSources[asset_];
        aggr = address(source.aggregator);
        isUSD = source.returnsUSD;
    }
}
