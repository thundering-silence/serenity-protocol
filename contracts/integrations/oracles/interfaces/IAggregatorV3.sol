// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

interface IAggregatorV3 {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    /**
     * getRoundData and latestRoundData should both raise "No data present"
     * if they do not have data to report, instead of returning unset values
     * which could be misinterpreted as actual reported values.
     * they return with answer = 0 instead
     */
    function getRoundData(uint80)
        external
        view
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        );

    function latestRoundData()
        external
        view
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        );
}
