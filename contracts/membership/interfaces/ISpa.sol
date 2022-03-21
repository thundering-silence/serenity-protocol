// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../../IOwnable.sol";
import "../../libraries/DataTypesLib.sol";
import "../../staking/interfaces/IZenGarden.sol";

interface ISpa is IERC20, IOwnable {
    function zenGarden() external view returns (IZenGarden);

    function treasury() external view returns (address);

    function tierConfig(DataTypes.Tier tier_)
        external
        view
        returns (DataTypes.TierConfig memory);

    function accountData(address account)
        external
        view
        returns (DataTypes.MemberData memory);

    function join(uint256 amount, uint256 lockPeriod) external;

    function prolongLock(uint256 additionalTime) external;

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function calculateFee(address account, uint256 baseFee)
        external
        view
        returns (uint256);

    function calculateLiquidationThreshold(
        address account,
        uint256 baseCollateral,
        uint256 maxCollateral
    ) external view returns (uint256);

    function updateTierConfig(
        DataTypes.Tier tier_,
        DataTypes.TierConfig memory config
    ) external;

    function withdrawalPenalty() external view returns (uint256);

    function forceWithdraw() external;

    function updateZenGarden(address value) external;

    function updateTreasury(address value) external;

    function updateMinLockAmount(uint256 value) external;
}
