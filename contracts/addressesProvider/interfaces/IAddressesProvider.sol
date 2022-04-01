// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "../../IOwnable.sol";

interface IAddressesProvider is IOwnable {
    function mind() external view returns (address);

    function zenGarden() external view returns (address);

    function spa() external view returns (address);

    function oracle() external view returns (address);

    function swapper() external view returns (address);

    function feesCollector() external view returns (address);

    function rewardsManager() external view returns (address);

    function treasury() external view returns (address);

    function entrypoint() external view returns (address);

    // ADMIN METHODS
    function updateMIND(address value) external;

    function updateZenGarden(address value) external;

    function updateThermae(address value) external;

    function updateOracle(address value) external;

    function updateSwapper(address value) external;

    function updateFeesCollector(address value) external;

    function updateRewardsManager(address value) external;

    function updateTreasury(address value) external;

    function updateEntryPoint(address value) external;
}
