// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

import "../libraries/DataTypesLib.sol";

contract Ticketing is ERC1155(""), Ownable {
    mapping(uint256 => uint256) public tokenDiscount; // 1 ether == 100%
    uint256 private _maxId;

    event UpdateTokenDiscount(uint256 id, uint256 discount);
    event UpdateMaxId(uint256 value);

    function accountDiscount(address account) public view returns (uint256) {
        uint256 discount;
        for (uint256 i = 0; i <= _maxId; ++i) {
            uint256 balance = balanceOf(account, i);
            discount += (balance * tokenDiscount[i]) / 1 ether;
        }
        return discount > 1 ether ? 1 ether : discount;
    }

    function discountForToken(uint256 id) public view returns (uint256) {
        return tokenDiscount[id];
    }

    function maxId() public view returns (uint256) {
        return _maxId;
    }

    // ADMIN METHODS
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public onlyOwner {
        _mint(to, id, amount, data);
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public onlyOwner {
        _mintBatch(to, ids, amounts, data);
    }

    function updateURI(string memory newUri) public onlyOwner {
        _setURI(newUri);
    }

    function updateTokenDiscount(uint256 id, uint256 discount)
        public
        onlyOwner
    {
        tokenDiscount[id] = discount;
        emit UpdateTokenDiscount(id, discount);
    }

    function updateMaxId(uint256 value) public onlyOwner {
        _maxId = value;
        emit UpdateMaxId(value);
    }

    // function updateTierConfig(
    //     DataTypes.Tier tier,
    //     DataTypes.TierConfig memory config
    // ) public onlyOwner {
    //     _tiers[tier] = config;
    //     emit TierConfigUpdate(
    //         tier,
    //         config.feeReductionPercent,
    //         config.maxMembers
    //     );
    // }
}
