// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../IOwnable.sol";

interface IZenGarden is IERC20, IOwnable {
    function rewardPerSharePrecision() external pure returns (uint256);

    function mind() external view returns (IERC20);

    function rewards() external view returns (address[] memory);

    function depositReward(IERC20 reward, uint256 amount) external;

    function enter(uint256 amount) external;

    function exit(uint256 amount) external;

    function claimableAmount(IERC20 reward) external view returns (uint256);

    function claim(IERC20 reward) external;

    function multiClaim(address[] memory rewardAddresses) external;

    function depositedAmount(address account) external view returns (uint256);

    function transferDepositedAmount(
        address from,
        address to,
        uint256 amount
    ) external;

    function updateThermae(address spa) external;

    function pauseReward(address reward) external;

    function unpauseReward(address reward) external;

    function addReward(address token) external;

    function removeReward(address reward) external;
}
