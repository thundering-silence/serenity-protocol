const { ethers } = require('hardhat');
const fs = require('fs')

require('dotenv').config()
const env = process.env;

async function main() {
    if (!env.ORACLE || !env.SWAPPER) {
        throw Error('No Oracle or Swapper address set in .env baby')
    }
    const oracle = env.ORACLE;
    const EntryPointStorage = await ethers.getContractFactory("EntryPointStorage");
    const entryPointStorage = await EntryPointStorage.deploy(oracle);
    await entryPointStorage.deployed();
    console.log(`EntryPointStorage deployed to ${entryPointStorage.address}`);
    fs.appendFileSync('.env', `ENTRYPOINT_STORAGE=${entryPointStorage.address}\n`);

    const EntryPoint = await ethers.getContractFactory("EntryPoint");
    const entryPoint = await EntryPoint.deploy(entryPointStorage.address, env.SWAPPER);
    await entryPoint.deployed();
    console.log(`EntryPoint deployed to ${entryPoint.address}`);
    fs.appendFileSync('.env', `ENTRYPOINT=${entryPoint.address}\n`);

}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
