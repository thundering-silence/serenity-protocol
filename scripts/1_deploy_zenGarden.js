const { ethers } = require('hardhat');
const fs = require('fs')

require('dotenv').config()
const env = process.env;

async function main() {
    console.log("DEPLOYING ZEN GARDEN")
    if (!env.MIND) {
        throw Error('No MIND address set in .env!')
    }
    const ZenGarden = await ethers.getContractFactory("ZenGarden");
    const BODY = await ZenGarden.deploy(`${env.MIND}`);
    await BODY.deployed();
    console.log("ZenGarden deployed to:", BODY.address);
    fs.appendFileSync('.env', `BODY=${BODY.address}\n`);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
