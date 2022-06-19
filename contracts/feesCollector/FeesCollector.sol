// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../pool/interfaces/IPool.sol";
import "../staking/interfaces/IZenGarden.sol";

import "../libraries/DataTypesLib.sol";

import "hardhat/console.sol";

contract FeesCollector is Ownable {
    using SafeERC20 for IERC20;

    address internal _treasury;
    IZenGarden internal _zenGarden;
    address internal _dev;

    mapping(IPool => DataTypes.FeeDistributionParams)
        internal _poolFeeDistributionParams;

    event TreasuryUpdate(address indexed treasury);
    event ZenGardenUpdate(address indexed zenGarden);
    event DevUpdate(address indexed dev);
    event FeeDistributionParamsUpdate(
        address indexed pool,
        uint256 treasury,
        uint256 zenGarden,
        uint256 dev
    );
    event Distribute(address indexed pool);

    constructor(
        address treasury_,
        address zenGarden_,
        address dev_
    ) {
        _treasury = treasury_;
        _zenGarden = IZenGarden(zenGarden_);
        _dev = dev_;
    }

    function feeDistributionParams(IPool pool)
        public
        view
        returns (DataTypes.FeeDistributionParams memory)
    {
        return _poolFeeDistributionParams[pool];
    }

    /**
     * @notice Update the accumulated fees for a pool
     * @dev only pools can successfully invoke this method
     * @param poolAddress - the pool to update fees
     * @param amount - the amount to add to accumulated fees
     */
    function updateAccumulatedAmount(address poolAddress, uint256 amount)
        public
    {
        require(_msgSender() == poolAddress, "Sender is not Pool");
        IPool pool = IPool(poolAddress);
        require(IERC20(pool.underlying()).balanceOf(address(this)) >= amount);
        DataTypes.FeeDistributionParams
            storage params = _poolFeeDistributionParams[pool];
        params.accumulatedAmount += amount;
    }

    /**
     * @notice Distributes rewards accumulated following the configuration
     * @dev Anyone can call this function
     * @param pool - the pool for which to distribute rewards
     */
    function distribute(IPool pool) public {
        DataTypes.FeeDistributionParams
            storage params = _poolFeeDistributionParams[pool];
        require(params.treasury > 0, "DISTRIBUTE: Treasury cut is 0");
        require(params.zenGarden > 0, "DISTRIBUTE: Zen Garden cut is 0");
        console.log(params.accumulatedAmount);

        uint256 zenGardenAmount = (params.zenGarden *
            params.accumulatedAmount) / 1 ether;
        uint256 treasuryAmount = (params.treasury * params.accumulatedAmount) /
            1 ether;
        uint256 devAmount = (params.dev * params.accumulatedAmount) / 1 ether;
        console.log("zenGardenAmount=%s", zenGardenAmount);
        console.log("treasuryAmount=%s", treasuryAmount);
        console.log("devAmount=%s", devAmount);
        IERC20 token = IERC20(pool.underlying());

        token.safeIncreaseAllowance(address(_zenGarden), zenGardenAmount);
        _zenGarden.depositReward(token, zenGardenAmount);

        token.safeTransfer(_treasury, treasuryAmount);
        token.safeTransfer(_dev, devAmount);

        params.accumulatedAmount = 0;

        emit Distribute(address(pool));
    }

    // ADMIN METHODS
    function setFeeDistributionParams(
        IPool pool,
        DataTypes.FeeDistributionParams memory params
    ) public onlyOwner {
        DataTypes.FeeDistributionParams
            storage distParams = _poolFeeDistributionParams[pool];
        distParams.treasury = params.treasury;
        distParams.zenGarden = params.zenGarden;
        distParams.dev = params.dev;
        emit FeeDistributionParamsUpdate(
            address(pool),
            params.treasury,
            params.zenGarden,
            params.dev
        );
    }

    function updateTreasury(address treasury_) public onlyOwner {
        _treasury = treasury_;
        emit TreasuryUpdate(treasury_);
    }

    function zenGardenUpdate(IZenGarden zenGarden_) public onlyOwner {
        _zenGarden = zenGarden_;
        emit ZenGardenUpdate(address(zenGarden_));
    }

    function devUpdate(address dev_) public onlyOwner {
        _dev = dev_;
        emit DevUpdate(dev_);
    }
}
