// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/utils/math/SafeMath.sol";
// import "./uniLib/FixedPoint.sol";

// import "hardhat/console.sol";

// interface IUniswapV2Factory {
//     function getPair(address tokenA, address tokenB)
//         external
//         view
//         returns (address pair);
// }

// interface IUniswapV2Pair {
//     function token0() external view returns (address);

//     function getReserves()
//         external
//         view
//         returns (
//             uint112 reserve0,
//             uint112 reserve1,
//             uint32 blockTimestampLast
//         );

//     function price0CumulativeLast() external view returns (uint256);

//     function price1CumulativeLast() external view returns (uint256);
// }

// library UniswapLibrary {
//     using SafeMath for uint112;
//     using FixedPoint for *;

//     function getAssetPrice(
//         address dexFactory_,
//         address asset_,
//         address denominator_
//     ) internal view returns (uint256 quote, bool inverted) {
//         IUniswapV2Factory dexFactory = IUniswapV2Factory(dexFactory_);
//         IUniswapV2Pair pair = IUniswapV2Pair(
//             dexFactory.getPair(asset_, denominator_)
//         );
//         (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

//         // console.log("reserve0=%s | reserve1=%s", uint(reserve0), uint(reserve1));

//         inverted = false;
//         quote = asset_ == pair.token0()
//             ? reserve1.div(reserve0)
//             : reserve0.div(reserve1);
//         // if the value of token0 is less than the value of token1 the quotient will be <1
//         // and be rounded to 0. Return the other quotient with a inverted bool instead.
//         // make sure to reverse the division later on.
//         if (quote == 0) {
//             inverted = true;
//             quote = asset_ == pair.token0()
//                 ? reserve0.div(reserve1)
//                 : reserve1.div(reserve0);
//         }
//     }
// }
