// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../membership/interfaces/ITicketing.sol";
import "../membership/interfaces/IThermae.sol";

contract PerkAggregator is Ownable {
    ITicketing internal _ticketing;
    IThermae internal _thermae;
    uint256 internal _calmThreshold = 100 ether;
    uint256 internal _peacefulThreshold = 1000 ether;

    event UpdateCalmThreshold(uint256 value);
    event UpdatePeacefulThreshold(uint256 value);

    constructor(address membership_, address thermae_) {
        _ticketing = ITicketing(membership_);
        _thermae = IThermae(thermae_);
    }

    /**
     * @notice Calculate fee starting from basefee by looking at the tier the user belongs to
     * @param account - the account for which to calculate the fee
     * @param baseFee - the maximum fee payable
     * @return fee - the fee to pay
     */
    function calculateFee(address account, uint256 baseFee)
        public
        view
        returns (uint256 fee)
    {
        uint256 ticketDiscount = _ticketing.accountDiscount(account);
        uint256 ticketCut = (baseFee * 1 ether) / ticketDiscount;

        if (ticketCut == 1 ether) {
            fee = 0;
        } else {
            fee = (baseFee * 1 ether) / ticketCut;

            uint256 membershipDiscount;
            DataTypes.MemberData memory data = _thermae.accountData(account);
            if (data.depositedAmount >= _peacefulThreshold) {
                membershipDiscount = baseFee / 2; // 50%
            } else if (data.depositedAmount >= _calmThreshold) {
                membershipDiscount = (baseFee * 3) / 4; // 75%
            }

            fee = fee - membershipDiscount;
        }
    }

    /**
     * @notice Calculate the liquidation threshold for the account
     * @param account - the account for which to calculate the threshold
     * @param baseThreshold - the base collateralFactor set on the pool
     * @param maxThreshold - the maximum collateralFactor set on the pool
     * @return uint - the liquidation threshold
     */
    function calculateLiquidationThreshold(
        address account,
        uint256 baseThreshold,
        uint256 maxThreshold
    ) public view returns (uint256) {
        uint256 delta = maxThreshold - baseThreshold;

        uint256 ticketDiscount = _ticketing.accountDiscount(account);
        uint256 ticketProtection = (delta * 1 ether) / ticketDiscount;

        uint256 extraProtection;
        DataTypes.MemberData memory data = _thermae.accountData(account);
        if (data.depositedAmount >= _peacefulThreshold) {
            extraProtection = delta / 2;
        } else if (data.depositedAmount >= _calmThreshold) {
            return extraProtection = delta / 4;
        }
        uint256 sum = baseThreshold + extraProtection + ticketProtection;
        return sum > maxThreshold ? maxThreshold : sum;
    }

    // ADMIN METHODS
    function updateCalmThreshold(uint256 newThreshold) public onlyOwner {
        _calmThreshold = newThreshold;
        emit UpdateCalmThreshold(newThreshold);
    }

    function updatePeacefulThreshold(uint256 newThreshold) public onlyOwner {
        _peacefulThreshold = newThreshold;
        emit UpdatePeacefulThreshold(newThreshold);
    }
}
