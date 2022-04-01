// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

contract AddressesProvider is Ownable {
    address internal MIND;
    address internal ZEN_GARDEN;
    address internal SPA;
    address internal ORACLE;
    address internal SWAPPER;
    address internal FEES_COLLECTOR;
    address internal REWARDS_MANAGER;
    address internal TREASURY;
    address internal ENTRY_POINT;

    event Update(string key, address value);

    function mind() public view returns (address) {
        return MIND;
    }

    function zenGarden() public view returns (address) {
        return ZEN_GARDEN;
    }

    function spa() public view returns (address) {
        return SPA;
    }

    function oracle() public view returns (address) {
        return ORACLE;
    }

    function swapper() public view returns (address) {
        return SWAPPER;
    }

    function feesCollector() public view returns (address) {
        return FEES_COLLECTOR;
    }

    function rewardsManager() public view returns (address) {
        return REWARDS_MANAGER;
    }

    function treasury() public view returns (address) {
        return TREASURY;
    }

    function entrypoint() public view returns (address) {
        return ENTRY_POINT;
    }

    // ADMIN METHODS
    function updateMIND(address value) public onlyOwner {
        MIND = value;
        emit Update("MIND", value);
    }

    function updateZenGarden(address value) public onlyOwner {
        ZEN_GARDEN = value;
        emit Update("ZEN_GARDEN", value);
    }

    function updateThermae(address value) public onlyOwner {
        SPA = value;
        emit Update("SPA", value);
    }

    function updateOracle(address value) public onlyOwner {
        ORACLE = value;
        emit Update("ORACLE", value);
    }

    function updateSwapper(address value) public onlyOwner {
        SWAPPER = value;
        emit Update("SWAPPER", value);
    }

    function updateFeesCollector(address value) public onlyOwner {
        FEES_COLLECTOR = value;
        emit Update("FEES_COLLECTOR", value);
    }

    function updateRewardsManager(address value) public onlyOwner {
        REWARDS_MANAGER = value;
        emit Update("REWARDS_MANAGER", value);
    }

    function updateTreasury(address value) public onlyOwner {
        TREASURY = value;
        emit Update("TREASURY", value);
    }

    function updateEntryPoint(address value) public onlyOwner {
        ENTRY_POINT = value;
        emit Update("ENTRY_POINT", value);
    }
}
