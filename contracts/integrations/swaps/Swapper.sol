// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IUniForkRouter.sol";

import "hardhat/console.sol";

contract Swapper is Ownable {
    struct Routers {
        uint256 length;
        mapping(bytes32 => uint256) indexes;
        bytes32[] names;
        address[] addresses;
    }

    Routers internal _routers;
    // most likely always going to be WrappedNative
    mapping(address => mapping(address => address)) internal _bridges;

    event RouterUpdate(bytes32 name, address indexed address_, uint256 index);
    event RouterError(bytes32 name, address indexed address_, uint256 index);
    event BridgeUpdate(
        address indexed asset0,
        address indexed asset1,
        address indexed bridgeAsset
    );
    event SwapExecuted(
        address indexed router,
        address indexed tokenIn,
        uint256 amountIn,
        address indexed tokenOut,
        uint256 amountOut,
        address sender,
        address to
    );

    function routers()
        public
        view
        returns (bytes32[] memory, address[] memory)
    {
        return (_routers.names, _routers.addresses);
    }

    function updateRouter(bytes32 name, address address_) public onlyOwner {
        uint256 index = _routers.indexes[name];
        if (index != 0) {
            _routers.addresses[index] = address_;
        } else {
            index = _routers.length;
            _routers.names.push(name);
            _routers.addresses.push(address_);
            _routers.length += 1;
        }
        emit RouterUpdate(name, address_, index);
    }

    function bridgeFor(address token0, address token1)
        public
        view
        onlyOwner
        returns (address)
    {
        return _bridges[token0][token1];
    }

    function updateBridge(
        address assetIn,
        address assetOut,
        address bridge
    ) public onlyOwner {
        _bridges[assetIn][assetOut] = bridge;
        emit BridgeUpdate(assetIn, assetOut, bridge);
    }

    function getBestSwapIn(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    )
        public
        view
        returns (
            uint256 index,
            uint256 bestQuote,
            bool[] memory
        )
    {
        uint256 length = _routers.length;
        bool[] memory errors = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            IUniForkRouter router = IUniForkRouter(_routers.addresses[i]);
            try
                router.getAmountsOut(amountIn, _buildPath(tokenIn, tokenOut))
            returns (uint256[] memory quotes) {
                if (quotes[1] >= bestQuote) {
                    bestQuote = quotes[1];
                    index = i;
                }
            } catch {
                errors[i] = true;
            }
        }
        return (index, bestQuote, errors);
    }

    function getBestSwapOut(
        address tokenOut,
        uint256 amountOut,
        address tokenIn
    )
        public
        view
        returns (
            uint256 index,
            uint256 bestQuote,
            bool[] memory
        )
    {
        uint256 length = _routers.length;
        bool[] memory errors = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            IUniForkRouter router = IUniForkRouter(_routers.addresses[i]);
            try
                router.getAmountsIn(amountOut, _buildPath(tokenIn, tokenOut))
            returns (uint256[] memory quotes) {
                if (quotes[quotes.length - 1] <= bestQuote) {
                    bestQuote = quotes[quotes.length - 1];
                    index = i;
                }
            } catch {
                errors[i] = true;
            }
        }
        return (index, bestQuote, errors);
    }

    struct SwapData {
        address tokenIn;
        uint256 amountIn;
        address tokenOut;
        uint256 amountOut;
        address to;
        uint256 deadline;
    }

    function swapExactTokensToTokens(SwapData memory vars)
        public
        returns (uint256)
    {
        (uint256 index, , ) = getBestSwapIn(
            vars.tokenIn,
            vars.amountIn,
            vars.tokenOut
        );

        IUniForkRouter router = IUniForkRouter(_routers.addresses[index]);

        uint256[] memory amounts = router.swapExactTokensForTokens(
            vars.amountIn,
            vars.amountOut,
            _buildPath(vars.tokenIn, vars.tokenOut),
            vars.to,
            vars.deadline
        );

        emit SwapExecuted(
            address(router),
            vars.tokenIn,
            vars.amountIn,
            vars.tokenOut,
            amounts[amounts.length - 1],
            _msgSender(),
            vars.to
        );

        return amounts[0];
    }

    function swapTokensForExactTokens(SwapData memory vars)
        public
        returns (uint256)
    {
        (uint256 index, , ) = getBestSwapOut(
            vars.tokenOut,
            vars.amountOut,
            vars.tokenIn
        );

        IUniForkRouter router = IUniForkRouter(_routers.addresses[index]);

        uint256[] memory amounts = router.swapTokensForExactTokens(
            vars.amountOut,
            vars.amountIn,
            _buildPath(vars.tokenIn, vars.tokenOut),
            vars.to,
            vars.deadline
        );

        emit SwapExecuted(
            address(router),
            vars.tokenIn,
            vars.amountIn,
            vars.tokenOut,
            amounts[amounts.length - 1],
            _msgSender(),
            vars.to
        );

        return amounts[0];
    }

    function _buildPath(address token0, address token1)
        internal
        view
        returns (address[] memory)
    {
        address bridgeToken = bridgeFor(token0, token1);
        address[] memory quickPath = new address[](2);
        address[] memory detourPath = new address[](3);
        if (bridgeToken == address(0)) {
            quickPath[0] = token0;
            quickPath[1] = token1;
            return quickPath;
        } else {
            detourPath[0] = token0;
            detourPath[1] = bridgeToken;
            detourPath[2] = token1;
            return detourPath;
        }
    }
}
