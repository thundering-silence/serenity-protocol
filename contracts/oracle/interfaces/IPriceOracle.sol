// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "../../IOwnable.sol";

interface IPriceOracle is IOwnable {
    function setFallbackOracle(address) external;

    function getFallbackOracle() external;

    function setAssetSource(address, address) external;

    function setAssetsSources(address[] calldata, address[] calldata) external;

    function getAssetSource(address) external view returns (address, bool);

    function getAssetPrice(address) external view returns (uint256);

    function getAssetsPrices(address[] calldata)
        external
        view
        returns (uint256[] memory);
}
