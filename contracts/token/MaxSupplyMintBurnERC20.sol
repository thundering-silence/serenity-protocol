// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MaxSupplyMintBurnERC20 is ERC20, AccessControl {
    uint256 public immutable maxSupply;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor(
        string memory name_,
        string memory ticker_,
        uint256 maxSupply_
    ) ERC20(name_, ticker_) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        maxSupply = maxSupply_ == 0 ? 2**256 - 1 : maxSupply_;
    }

    // Remember to grant MINTER ROLE first!
    function mint(address account_, uint256 amount_)
        public
        onlyRole(MINTER_ROLE)
    {
        uint256 actualAmount = (totalSupply() + amount_) > maxSupply
            ? (maxSupply - totalSupply())
            : amount_;
        _mint(account_, actualAmount);
    }

    // Remember to grant BURN_ROLE first!
    function burn(address account_, uint256 amount_)
        public
        onlyRole(BURNER_ROLE)
    {
        _burn(account_, amount_);
    }
}
