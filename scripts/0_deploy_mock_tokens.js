const { ethers } = require('hardhat');
const { utils, constants, BigNumber } = require('ethers')
const fs = require('fs');

require('dotenv').config()

const tokensToCreate = [
    ['Chainlink Link', 'LINK'],
    ['Circle USD', 'USDC'],
    ['Tether USD', 'USDT'],
    ['DAI', 'DAI'],
    ['Wrapped ETH', 'WETH'],
    ['Wrapped BTC', 'WBTC'],
]

async function main() {
    console.log("DEPLOYING TOKENS")

    this.signers = await ethers.getSigners();
    this.user = this.signers[0]
    const recipientAddress = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
    const MSMBERC20 = await ethers.getContractFactory("MaxSupplyMintBurnERC20");

    const wNative = await MSMBERC20.deploy('Wrapped Native', 'WNATIVE', 0);
    await wNative.deployed();
    console.log(`WNATIVE deployed to ${wNative.address}`);
    fs.appendFileSync('.env', `WNATIVE=${wNative.address}\n`);

    await Promise.all(tokensToCreate.map(async (tokenData) => {
        const token = await MSMBERC20.deploy(tokenData[0], tokenData[1], 0);
        await token.deployed();
        console.log(`${tokenData[1]} deployed to ${token.address}`);
        fs.appendFileSync('.env', `${tokenData[1]}=${token.address}\n`);
        await token.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address);
        await token.functions.mint(recipientAddress, `${999 * 1e18}`);
    }))

    const mind = await MSMBERC20.deploy('Mind', 'MIND', constants.WeiPerEther.mul(BigNumber.from(`${1e9}`)));
    await mind.deployed();
    console.log(`MIND deployed to ${mind.address}`);

    fs.appendFileSync('.env', `MIND=${mind.address}\n`);

    await wNative.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address);
    await wNative.functions.mint(recipientAddress, `${999 * 1e18}`);



    await mind.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address);
    await mind.functions.mint(recipientAddress, `${999 * 1e18}`);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
