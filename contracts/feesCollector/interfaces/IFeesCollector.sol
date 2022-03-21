// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "../../libraries/DataTypesLib.sol";
import "../../pool/interfaces/IPool.sol";
import "../../staking/interfaces/IZenGarden.sol";

import "../../IOwnable.sol";

interface IFeesCollector is IOwnable {
    function feeDistributionParams(IPool pool)
        external
        view
        returns (DataTypes.FeeDistributionParams memory);

    function updateAccumulatedAmount(address poolAddress, uint256 amount)
        external;

    function distribute(IPool pool) external;

    // ADMIN METHODS
    function setDistributionParams(
        IPool pool,
        DataTypes.FeeDistributionParams memory params
    ) external;

    function updateTreasury(address treasury_) external;

    function zenGardenUpdate(IZenGarden zenGarden_) external;

    function devUpdate(address dev_) external;
}
