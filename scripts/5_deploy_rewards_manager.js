const { ethers } = require('hardhat');
const { utils } = require('ethers');

require('dotenv').config()
const env = process.env;



async function main() {
    if (!env.REWARDED_POOL) {
        throw Error('No Pool set for rewards')
    }
    const Pool = await ethers.getContractFactory("Pool");
    const MSMBERC20 = await ethers.getContractFactory("MaxSupplyMintBurnERC20");
    const Manager = await ethers.getContractFactory("RewardsManager");

    this.signers = await ethers.getSigners();
    this.user = this.signers[0]
    const mind = await MSMBERC20.deploy('Mind', 'MIND', 0);
    await mind.deployed();
    console.log(`MIND deployed to ${mind.address}`);

    await mind.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address);
    await mind.functions.grantRole(utils.id("MINTER_ROLE"), env.REWARDED_POOL);
    await mind.functions.mint(this.user.address, `${999 * 1e18}`);

    const pool = await Pool.attach(env.REWARDED_POOL)
    await pool.functions.grantRole(utils.id("ADMIN_ROLE"), this.user.address);
    await pool.functions.grantRole(utils.id("DELEGATOR_ROLE"), this.user.address);

    const manager = await Manager.deploy(env.REWARDED_POOL);
    await manager.deployed()

    await pool.functions.setRewardsManager(manager.address);
    await mind.functions.increaseAllowance(manager.address, `${999 * 1e18}`);
    await manager.functions.setRewardConfig(mind.address, `${.0002 * 1e18}`, Math.ceil(Date.now() / 1000) + 3600*24)
    await manager.activateReward(mind.address)

}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
