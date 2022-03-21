const { ethers } = require('hardhat');
const {utils, constants, BigNumber} = require('ethers')
const fs = require('fs');

require('dotenv').config()

async function main() {
    console.log("DEPLOYING TOKENS")

    this.signers = await ethers.getSigners();
    this.user = this.signers[0]
    const recipientAddress = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
    const MSMBERC20 = await ethers.getContractFactory("MaxSupplyMintBurnERC20");

    const wNative = await MSMBERC20.deploy('Wrapped Native', 'WNATIVE', 0);
    await wNative.deployed();
    console.log(`WNATIVE deployed to ${wNative.address}`);

    const link = await MSMBERC20.deploy('Chainlink Link', 'LINK', 0);
    await link.deployed();
    console.log(`LINK deployed to ${link.address}`);

    const mind = await MSMBERC20.deploy('Mind', 'MIND', constants.WeiPerEther.mul(BigNumber.from(`${1e9}`)));
    await mind.deployed();
    console.log(`MIND deployed to ${mind.address}`);

    fs.appendFileSync('.env', `WNATIVE=${wNative.address}\n`);
    fs.appendFileSync('.env', `LINK=${link.address}\n`);
    fs.appendFileSync('.env', `MIND=${mind.address}\n`);

    await wNative.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address);
    await wNative.functions.mint(recipientAddress, `${999 * 1e18}`);

    await link.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address);
    await link.functions.mint(recipientAddress, `${999 * 1e18}`);

    await mind.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address);
    // await link.functions.mint(recipientAddress, `${999 * 1e18}`);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
