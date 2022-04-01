// // SPDX-License-Identifier: GPL-3.0-only
// pragma solidity ^0.8.4;

// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import "../integrations/swaps/interfaces/ISwapper.sol";
// import "../main/interfaces/IEntryPoint.sol";

// contract SelfRepaying is Ownable {
//     using SafeERC20 for IERC20;

//     IEntryPoint public immutable _entryPoint;

//     address private _debtToken;

//     constructor(address entryPoint_) {
//         _entryPoint = IEntryPoint(entryPoint_);
//     }

//     function deposit(address asset, uint256 amount) public onlyOwner {
//         IERC20(asset).safeTransferFrom(_msgSender(), address(this), amount);
//         _entryPoint.deposit(asset, amount);
//     }

//     function borrow(address asset, uint256 amount) public onlyOwner {
//         require(_debtToken == address(0), "BORROW: only one loan per vault");
//         _entryPoint.borrow(asset, amount);
//         IERC20(asset).safeTransfer(_msgSender(), amount);
//     }

//     function repay(address asset, uint256 amount) public onlyOwner {
//         _entryPoint.repay(asset, amount);
//     }

//     function withdraw(address asset, uint256 amount) public onlyOwner {
//         _entryPoint.withdraw(asset, amount);
//         IERC20(asset).safeTransfer(_msgSender(), amount);
//     }
// }
