const { ethers } = require('hardhat');
const { constants } = require('ethers')
const fs = require('fs')

require('dotenv').config()
const env = process.env;

async function main() {
    console.log("DEPLOYING ORACLE")
    if (!env.WNATIVE || !env.LINK) {
        throw Error('No WNATIVE or LINK address set in .env baby')
    }
    const PriceOracle = await ethers.getContractFactory("PriceOracle");
    const oracle = await PriceOracle.deploy(env.WNATIVE);
    await oracle.deployed();

    console.log("PriceOracle deployed to:", oracle.address);
    fs.appendFileSync('.env', `ORACLE=${oracle.address}\n`);
    await oracle.functions.setAssetSource(env.WNATIVE, env.CHAINLINK_WNATIVE_AGGREGATOR, true);
    await oracle.functions.setAssetSource(env.LINK, env.CHAINLINK_LINK_AGGREGATOR, true);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
