const { ethers } = require('hardhat');
const fs = require('fs')

require('dotenv').config()
const env = process.env;

async function main() {
    console.log("DEPLOYING FEES COLLECTOR")
    if (!env.BODY || !env.TREASURY || !env.DEV) {
        throw Error('No BODY or TREASURY or DEV address set in .env!')
    }
    const FeesCollector = await ethers.getContractFactory("FeesCollector");
    const feesCollector = await FeesCollector.deploy(
        env.TREASURY,
        env.BODY,
        env.DEV
    )
    await feesCollector.deployed()

    console.log("FeesCollector deployed to:", feesCollector.address);
    fs.appendFileSync('.env', `FEES_COLLECTOR=${feesCollector.address}\n`);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
