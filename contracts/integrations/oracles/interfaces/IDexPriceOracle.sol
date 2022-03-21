// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;
import "../../../IOwnable.sol";

interface IDexPriceOracle is IOwnable {
    function getAssetPrice(address, address)
        external
        view
        returns (uint256, bool);
}
