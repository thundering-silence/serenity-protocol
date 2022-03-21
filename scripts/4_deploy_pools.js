const { ethers } = require('hardhat');
const fs = require('fs');
const { utils } = require('ethers');

require('dotenv').config()
const env = process.env;

async function main() {
    const signers = await ethers.getSigners();
    const signerAddr = await signers[0].getAddress();
    if (!env.ENTRYPOINT) {
        throw Error('No ENTRYPOINT address set n .env baby')
    }
    if (!env.WNATIVE || !env.LINK) {
        throw Error('No WNATIVE or LINK address set in .env baby')
    }
    const Entrypoint = await ethers.getContractFactory("EntryPointStorage");
    const entrypoint = await Entrypoint.attach(env.ENTRYPOINT_STORAGE);
    const Pool = await ethers.getContractFactory("Pool")
    const tx0 = await entrypoint.createPool(
        env.WNATIVE,
        env.ORACLE,
        [
            `${0.75 * 1e18}`, // collateralFactor
            `${0.1 * 1e18}`, // liquidationFee
            `${0.2 * 1e18}`, // fee
            `${0.95 * 1e18}`, // maxLiquidationThreshold
            `${.08 / 100 * 1e18}` // flashFee
        ],
        [
            `${0}`, // baseRate,
            `${.07 * 1e18}`, // slope1
            `${5 * 1e18}`, // slope2
            `${.75 * 1e18}` // optimal Util
        ],
        signerAddr // treasury
    );
    const tx0Receipt = await tx0.wait()
    const event0 = tx0Receipt.events.find(e => e.event == 'NewPool')
    console.log(`Pool for: ${event0.args[0]} deployed to ${event0.args[1]}\n`);
    const NativePool = await Pool.attach(event0.args[1])
    await NativePool.grantRole(utils.id("DELEGATOR_ROLE"), env.ENTRYPOINT);

    const tx1 = await entrypoint.createPool(
        env.LINK,
        env.ORACLE,
        [
            `${0.75 * 1e18}`, // collateralFactor
            `${0.1 * 1e18}`, // liquidationFee
            `${0.2 * 1e18}`, // fee
            `${0.95 * 1e18}`, // maxLiquidationThreshold
            `${.08 / 100 * 1e18}`, // flashFee
        ],
        [
            `${0}`, // baseRate,
            `${.08 * 1e18}`, // slope1
            `${3 * 1e18}`, // slope2
            `${.65 * 1e18}`, // optimal Util
        ],
        signerAddr // treasury
    );
    const tx1Receipt = await tx1.wait()
    const event1 = tx1Receipt.events.find(e => e.event == 'NewPool')
    console.log(`Pool for: ${event1.args[0]} deployed to ${event1.args[1]}`);
    const LinkPool = await Pool.attach(event1.args[1])
    await LinkPool.grantRole(utils.id("DELEGATOR_ROLE"), env.ENTRYPOINT);
    fs.appendFileSync('.env', `REWARDED_POOL=${event1.args[1]}\n\n\n`);

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
