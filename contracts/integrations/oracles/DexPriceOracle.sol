// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

// import "@openzeppelin/contracts/access/Ownable.sol";
// import "./interfaces/IDexPriceOracle.sol";
// import {UniswapLibrary} from "./UniswapAdapter.sol";

// contract DexPriceOracle is IDexPriceOracle, Ownable {
//     using UniswapLibrary for address;

//     mapping(address => address) private _uniForkSourceForAsset; // Factory addresses

//     function setUniswapForkSourceForAsset(address asset_, address uniForkSource_) public onlyOwner {
//         _uniForkSourceForAsset[asset_] = uniForkSource_;
//     }

//     function getAssetPrice(address asset_, address denominator_) override public view returns (uint quote, bool inverted) {
//         // TODO - change this to read from a TWAP Oracle
//         // https://docs.uniswap.org/protocol/V2/guides/smart-contract-integration/building-an-oracle
//         address dexFactory = _uniForkSourceForAsset[asset_];
//         require(dexFactory != address(0), "No factory set for asset");
//         (quote, inverted) = dexFactory.getAssetPrice(asset_, denominator_);
//     }
// }
