const { ethers } = require('hardhat');
const { constants } = require('ethers')
const fs = require('fs')

require('dotenv').config()
const env = process.env;

const tiersData = [
    {
        feeReduction: `${.25 * 1e18}`,
        minLock: 3600 * 24 * 90, // 90 days
        ratio: 1
    },
    {
        feeReduction: `${.5 * 1e18}`,
        minLock: 3600 * 24 * 365, // 1 year
        ratio: 5
    },
    {
        feeReduction: `${1e18}`,
        minLock: 3600 * 24 * 365 * 2, // 2 years
        ratio: 10
    },
]

async function main() {
    console.log("DEPLOYING SPA")
    if (!env.BODY || !env.TREASURY) {
        throw Error('No BODY or TREASURY address set in .env!')
    }
    const Spa = await ethers.getContractFactory("Spa");
    const SOUL = await Spa.deploy(env.BODY, env.TREASURY, constants.WeiPerEther)
    await SOUL.deployed()

    await Promise.all(tiersData.map(async (t, i) => {
        await SOUL.functions.updateTierConfig(i, Object.values(t))
    }))

    const ZenGarden = await ethers.getContractFactory("ZenGarden");
    const zenGarden = await ZenGarden.attach(env.BODY)
    await zenGarden.functions.updateSpa(SOUL.address);

    console.log("Spa deployed to:", SOUL.address);
    fs.appendFileSync('.env', `SOUL=${SOUL.address}\n`);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
