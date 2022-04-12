// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../../libraries/DataTypesLib.sol";

interface ITicketing {
    function tierConfig(DataTypes.Tier tier)
        external
        view
        returns (DataTypes.TierConfig memory);

    function accountDiscount(address account) external view returns (uint256);

    // ADMIN METHODS
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external;

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external;

    function updateURI(string memory newUri) external;

    function updateTierConfig(
        DataTypes.Tier tier,
        DataTypes.TierConfig memory config
    ) external;
}
