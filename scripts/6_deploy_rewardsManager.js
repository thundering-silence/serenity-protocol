const { ethers } = require('hardhat');
const fs = require('fs')

require('dotenv').config()

async function main() {
    console.log("DEPLOYING REWARDS MANAGER")
    const Manager = await ethers.getContractFactory("RewardsManager");
    const manager = await Manager.deploy();
    await manager.deployed()

    console.log(`Rewards manager deployed to: ${manager.address}`)
    fs.appendFileSync('.env', `REWARDS_MANAGER=${manager.address}\n`);

}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
