// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "../../../IOwnable.sol";

interface ISwapper is IOwnable {
    function routers()
        external
        view
        returns (bytes32[] memory, address[] memory);

    function bridgeFor(address token0, address token1)
        external
        view
        returns (address);

    function updateRouter(bytes32 name, address address_) external;

    function updateBridge(
        address assetIn,
        address assetOut,
        address bridge
    ) external;

    function getBestSwapIn(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    )
        external
        view
        returns (
            uint256 index,
            uint256 bestQuote,
            address[] memory erroredRouters
        );

    function getBestSwapOut(
        address tokenOut,
        uint256 amountOut,
        address tokenIn
    )
        external
        view
        returns (
            uint256 index,
            uint256 bestQuote,
            bool[] memory
        );

    function swapExactTokensForTokens(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        address to,
        uint256 deadline
    ) external returns (uint256);

    function swapTokensForExactTokens(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 amountOut,
        address to,
        uint256 deadline
    ) external returns (uint256);
}
