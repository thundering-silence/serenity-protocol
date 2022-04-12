// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

interface IPerksAggregator {
    function calculateFee(address account, uint256 baseFee)
        external
        view
        returns (uint256 fee);

    function calculateLiquidationThreshold(
        address account,
        uint256 baseThreshold,
        uint256 maxThreshold
    ) external view returns (uint256);
}
