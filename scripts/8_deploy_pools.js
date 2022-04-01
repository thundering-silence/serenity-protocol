const { ethers } = require('hardhat');
const fs = require('fs');
const { utils, constants, BigNumber } = require('ethers');
const { solidityPack } = require('ethers/lib/utils');

require('dotenv').config()
const env = process.env;

async function main() {
    console.log("DEPLOYING POOLS")
    this.signers = await ethers.getSigners();
    this.user = this.signers[0]
    if (!env.WNATIVE || !env.LINK) {
        throw Error('No WNATIVE or LINK address set in .env!')
    }
    if (!env.MIND || !env.BODY || !env.SOUL) {
        throw Error('No MIND or BODY or SOUL address set in .env!')
    }
    if (!env.FEES_COLLECTOR || !env.REWARDS_MANAGER) {
        throw Error('No FEES_COLLECTOR or REWARDS_MANAGER address set in .env!')
    }
    if (!env.ENTRYPOINT_STORAGE || !env.ENTRYPOINT || !env.FEES_COLLECTOR) {
        throw Error('No ENTRYPOINT_STORAGE or ENTRYPOINT address set in .env!')
    }
    const MaxSupplyMintBurnERC20 = await ethers.getContractFactory("MaxSupplyMintBurnERC20")
    const ZenGarden = await ethers.getContractFactory("ZenGarden");
    const Thermae = await ethers.getContractFactory("Thermae");
    const FeesCollector = await ethers.getContractFactory("FeesCollector")
    const RewardsManager = await ethers.getContractFactory("RewardsManager")
    const Entrypoint = await ethers.getContractFactory("EntryPointStorage");
    const Pool = await ethers.getContractFactory("Pool")

    const mind = await MaxSupplyMintBurnERC20.attach(env.MIND)
    const zenGarden = await ZenGarden.attach(env.BODY)
    const feesCollector = await FeesCollector.attach(env.FEES_COLLECTOR)
    const rewardsManager = await RewardsManager.attach(env.REWARDS_MANAGER)
    const entrypoint = await Entrypoint.attach(env.ENTRYPOINT_STORAGE);

    const tx0 = await entrypoint.createPool(
        env.WNATIVE,
        env.FEES_COLLECTOR,
        [
            `${0.75 * 1e18}`, // collateralFactor
            `${0.1 * 1e18}`, // liquidationFee
            `${0.95 * 1e18}`, // maxLiquidationThreshold
            `${0.25 * 1e18}`, // fee
            true, // allow borrowing
        ],
        [
            `${0}`, // baseRate,
            `${.07 * 1e18}`, // slope1
            `${5 * 1e18}`, // slope2
            `${.75 * 1e18}` // optimal Util
        ],
        [
            true, // activate flash loans
            `${.0008 * 1e18}`, // flashFee 0.08%
        ]
    );
    const tx0Receipt = await tx0.wait()
    const event0 = tx0Receipt.events.find(e => e.event == 'NewPool')
    console.log(`Pool for: ${event0.args[0]} deployed to ${event0.args[1]}\n`);
    const NativePool = await Pool.attach(event0.args[1])
    await NativePool.grantRole(utils.id("DELEGATOR_ROLE"), env.ENTRYPOINT);

    const tx1 = await entrypoint.createPool(
        env.LINK,
        env.FEES_COLLECTOR,
        [
            `${0.75 * 1e18}`, // collateralFactor
            `${0.1 * 1e18}`, // liquidationFee
            `${0.95 * 1e18}`, // maxLiquidationThreshold
            `${0.15 * 1e18}`, // fee
            true, // allow borrowing
        ],
        [
            `${0}`, // baseRate,
            `${.07 * 1e18}`, // slope1
            `${5 * 1e18}`, // slope2
            `${.75 * 1e18}` // optimal Util
        ],
        [
            true, // activate flash loans
            `${.0008 * 1e18}`, // flashFee 0.08%
        ]
    );
    const tx1Receipt = await tx1.wait()
    const event1 = tx1Receipt.events.find(e => e.event == 'NewPool')
    console.log(`Pool for: ${event1.args[0]} deployed to ${event1.args[1]}`);
    const LinkPool = await Pool.attach(event1.args[1])
    await LinkPool.grantRole(utils.id("DELEGATOR_ROLE"), env.ENTRYPOINT);

    // zen garden
    await zenGarden.functions.addReward(env.WNATIVE)
    await zenGarden.functions.addReward(env.LINK)

    // rewards manager
    await mind.functions.mint(this.user.address, constants.WeiPerEther.mul(BigNumber.from(`${1e6}`)))
    await mind.functions.approve(rewardsManager.address, constants.MaxUint256)
    await rewardsManager.functions.updatePoolRewardConfig(
        NativePool.address,
        env.MIND,
        BigNumber.from(`${5 * 1e18}`),
        BigNumber.from(`${10 * 1e18}`)
    )
    await rewardsManager.functions.updatePoolRewardConfig(
        LinkPool.address,
        env.MIND,
        BigNumber.from(`${5 * 1e18}`),
        BigNumber.from(`${5 * 1e18}`)
    )
    await rewardsManager.functions.activateReward(env.MIND, this.user.address);

    // fees collector
    await feesCollector.functions.setFeeDistributionParams(
        NativePool.address,
        [
            `${.375 * 1e18}`,
            `${.375 * 1e18}`,
            `${.25 * 1e18}`,
            0
        ]
    )
    await feesCollector.functions.setFeeDistributionParams(
        LinkPool.address,
        [
            `${.375 * 1e18}`,
            `${.375 * 1e18}`,
            `${.25 * 1e18}`,
            0
        ]
    )

    // entry point
    await entrypoint.setPoolForUnderlying(event0.args[0], event0.args[1])
    await entrypoint.setPoolForUnderlying(event1.args[0], event1.args[1])
    await entrypoint.supportNewAsset(env.WNATIVE);
    await entrypoint.supportNewAsset(env.LINK);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
