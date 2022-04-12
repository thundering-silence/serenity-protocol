// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "../pool/interfaces/IPool.sol";
import "../flashloan/interfaces/IERC3156FlashBorrower.sol";

library DataTypes {
    /**@title Pool */
    struct LendingConfig {
        uint256 collateralFactor;
        uint256 liquidationFee;
        uint256 maxLiquidationThreshold;
        uint256 fee;
        bool allowBorrow;
    }

    struct FlashLoanConfig {
        bool active;
        uint256 fee;
    }

    struct InterestRateConfig {
        uint256 baseRate;
        uint256 slope1;
        uint256 slope2;
        uint256 optimalUtilisation;
    }

    /**@title Entrypoint */
    struct LiquidationCallVars {
        address account;
        address debtAsset;
        uint256 debtAmount;
        address collateralAsset;
        address recipient;
    }

    struct LiquidationInternalVars {
        IPool debtAssetPool;
        IPool collateralAssetPool;
        uint256 debtAssetPrice;
        uint256 collateralAssetPrice;
        uint256 debtAmount;
        uint256 collateralAmount;
        uint256 totalDebtValue;
        uint256 totalCollateralValue;
        uint256 fee;
        uint256 feeValue;
    }

    struct FlashloanCallData {
        uint8 intent; // 0 - default | 1 - collateralSwap | 2 - debtSwap | 3 - repayWithCollateral
        IERC3156FlashBorrower receiver;
        address asset;
        uint256 amount;
        // below only necessary for intents 1, 2 and 3
        address account;
        address toAsset;
        uint256 toAmount;
    }

    /**@title FeesCollector */
    struct FeeDistributionParams {
        uint256 treasury;
        uint256 zenGarden;
        uint256 dev;
        uint256 accumulatedAmount;
    }

    /**@title Membership */
    enum Tier {
        SERENE,
        PEACEFUL
    }

    struct TierConfig {
        uint256 feeReductionPercent;
        // uint256 minLockPeriod;
        // uint256 receiptRatio; // how much SOUL to mint as receipt for locking 1 BODY: 10 Serene | 5 Peaceful | 1 Calm
        uint16 maxMembers;
    }

    /**@title Thermae */
    struct MemberData {
        uint256 depositedAmount;
        uint256 unlockTime;
    }
}
