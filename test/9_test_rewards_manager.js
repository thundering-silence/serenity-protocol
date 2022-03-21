// const { expect } = require("chai");
// const { ethers } = require("hardhat");
// const { BigNumber, utils } = require("ethers");

// const routerABI = require('./utils/uniRouter.abi.json').abi;

// const poolConfig = {
//     collateralF: 0.75 * 1e18,
//     liquidationF: .1 * 1e18,
//     treasuryF: 0.2 * 1e18,
//     maxLiq: .95 * 1e18,
//     baseRate: 0,
//     slope1: .07 * 1e18,
//     slope2: 3 * 1e18,
//     optimalU: .65 * 1e18,
// }


// const interactions = [
//     {
//         signerIndex: 1,
//         action: "deposit",
//         amount: `${1e8}`
//     }
// ]


// describe("Pool - Rewards Manager interaction", function () {
//     before(async function () {
//         this.signers = await ethers.getSigners();
//         this.user = this.signers[0]

//         // Tokens
//         const ERC20 = await ethers.getContractFactory("MaxSupplyMintBurnERC20");
//         this.mockWrappedNative = await ERC20.deploy("WNATIVE", "NATIVE", 0);
//         // this.token = await ERC20.deploy("TKN2", "TKN2", 0);
//         await this.mockWrappedNative.deployed();
//         await this.mockWrappedNative.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address);
//         await this.mockWrappedNative.functions.mint(this.user.address, `${999 * 1e18}`);

//         await Promise.all(this.signers.map(async (s) => {
//             const tx = await this.mockWrappedNative.functions.mint(s.address, `${10 * 1e18}`)
//             await tx.wait()
//         }))


//         // // Router
//         // this.unirouter = new ethers.Contract("0x60aE616a2155Ee3d9A68541Ba4544862310933d4", routerABI, this.user);
//         // await this.mockWrappedNative.functions.increaseAllowance(this.unirouter.address, `${90 * 1e18}`);
//         // await this.token.functions.increaseAllowance(this.unirouter.address, `${450 * 1e18}`);
//         // await this.unirouter.addLiquidity(
//         //     this.mockWrappedNative.address,
//         //     this.token.address,
//         //     `${90 * 1e18}`,
//         //     `${450 * 1e18}`,
//         //     0,
//         //     0,
//         //     this.user.address,
//         //     Math.ceil(Date.now() / 1000 + 300)
//         // )
//         // Mock aggregator
//         const MockAggregatorV3 = await ethers.getContractFactory("MockAggregatorV3");
//         const mockAggr = await MockAggregatorV3.deploy();
//         await mockAggr.deployed();

//         /**
//          * *********************
//          * * mockWrappedNative worth $5
//          * *********************
//          */
//         await mockAggr.functions.setAnswer(`${5 * 1e8}`);
//         // DexPriceOracle
//         const DexOracle = await ethers.getContractFactory("DexPriceOracle");
//         this.dexOracle = await DexOracle.deploy();
//         await this.dexOracle.deployed();
//         await this.dexOracle.functions.setUniswapForkSourceForAsset(this.mockWrappedNative.address, process.env.UNISWAP_FACTORY);

//         // PriceOracle
//         const Oracle = await ethers.getContractFactory("PriceOracle");
//         this.oracle = await Oracle.deploy(
//             this.dexOracle.address,
//             this.mockWrappedNative.address
//         );
//         await this.oracle.deployed();
//         await this.oracle.functions.setAssetSource(
//             this.mockWrappedNative.address,
//             mockAggr.address,
//             true,
//         );

//         // Pool
//         const Pool = await ethers.getContractFactory("Pool");
//         this.pool = await Pool.deploy(
//             this.mockWrappedNative.address,
//             this.oracle.address,
//             BigNumber.from(`${poolConfig.collateralF}`),
//             BigNumber.from(`${poolConfig.liquidationF}`),
//             BigNumber.from(`${poolConfig.treasuryF}`),
//             BigNumber.from(`${poolConfig.graceF}`),
//             BigNumber.from(`${poolConfig.baseRate}`),
//             BigNumber.from(`${poolConfig.slope1}`),
//             BigNumber.from(`${poolConfig.slope2}`),
//             BigNumber.from(`${poolConfig.optimalU}`),
//             this.signers[1].address,
//             this.user.address
//         )
//         await this.pool.deployed();
//         await this.pool.functions.grantRole(utils.id("ADMIN_ROLE"), this.user.address);
//         await this.pool.functions.grantRole(utils.id("DELEGATOR_ROLE"), this.user.address);
//         await Promise.all(this.signers.map(async (s) => {
//             await this.pool.functions.grantRole(utils.id("DELEGATOR_ROLE"), s.address);
//         }))

//         // RewardsManager
//         const Manager = await ethers.getContractFactory("RewardsManager");
//         this.manager = await Manager.deploy(this.pool.address);
//         await this.manager.deployed()
//         await this.pool.functions.setRewardsManager(this.manager.address);
//         await this.mockWrappedNative.functions.mint(this.user.address, `${100 * 1e18}`);
//         await this.mockWrappedNative.functions.increaseAllowance(this.manager.address, `${100 * 1e18}`);
//         await this.manager.functions.setRewardConfig(this.mockWrappedNative.address, `${.2 * 1e18}`, Math.ceil(Date.now() / 1000) + 300)
//         await this.manager.activateReward(this.mockWrappedNative.address)
//     })

//     it("full rotation", async function () {
//         // deposit
//         await Promise.all(this.signers.map(async (s) => {
//             const pool = new ethers.Contract(this.pool.address, this.pool.interface, s)
//             const mockWrappedNative = new ethers.Contract(this.mockWrappedNative.address, this.mockWrappedNative.interface, s)
//             await mockWrappedNative.increaseAllowance(this.pool.address, `${10 * 1e18}`)
//             await pool.deposit(s.address, `${2 * 1e18}`)
//             await pool.setCollateral(true)
//             await new Promise(resolve => setTimeout(resolve, 500))
//         }))

//         // borrow
//         await Promise.all(this.signers.map(async (s) => {
//             const pool = new ethers.Contract(this.pool.address, this.pool.interface, s)
//             const tx = await pool.borrow(s.address, `${1e18}`)
//             await tx.wait()
//             await new Promise(resolve => setTimeout(resolve, 500))
//         }))

//         // repay
//         await Promise.all(this.signers.map(async (s) => {
//             const pool = new ethers.Contract(this.pool.address, this.pool.interface, s)
//             const tx = await pool.repay(s.address, `${2 * 1e18}`)
//             await tx.wait()
//             await new Promise(resolve => setTimeout(resolve, 500))
//         }))

//         // withdraw
//         await Promise.all(this.signers.map(async (s) => {
//             const pool = new ethers.Contract(this.pool.address, this.pool.interface, s)
//             const tx = await pool.withdraw(s.address, `${2 * 1e18}`)
//             await tx.wait()
//             await new Promise(resolve => setTimeout(resolve, 500))
//         }))

//     })

// })
