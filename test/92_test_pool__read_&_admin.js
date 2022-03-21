// const { expect } = require("chai");
// const { ethers } = require("hardhat");
// const { BigNumber, utils } = require("ethers");

// const tokens = [
//     {
//         // SPELL
//         asset: process.env.WNATIVE,
//         source: process.env.CHAINLINK_WNATIVE_AGGREGATOR,
//         isUSD: true
//     },
//     {
//         // SPELL
//         asset: "0xce1bffbd5374dac86a2893119683f4911a2f7814",
//         source: "0x4F3ddF9378a4865cf4f28BE51E10AECb83B7daeE",
//         isUSD: true
//     },
//     {
//         // JOE
//         asset: "0x6e84a6216ea6dacc71ee8e6b0a5b7322eebc0fdd",
//         source: "0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a",
//         isUSD: true
//     },
//     {
//         // BTC.e
//         asset: "0x50b7545627a5162f82a992c33b87adc75187b218",
//         source: "0x2779D32d5166BAaa2B2b658333bA7e6Ec0C65743",
//         isUSD: true
//     },
// ]

// const poolConfig = {
//     collateralF: 0.75 * 1e18,
//     liquidationF: .1 * 1e18,
//     treasuryF: 0.2 * 1e18,
//     maxLiq: .95 * 1e18,
//     baseRate: 0,
//     slope1: .07 * 1e18,
//     slope2: 300 * 1e18,
//     optimalU: 0.65 * 1e18,
// }


// describe("Pool - Public and Admin interaction", function () {
//     before(async function () {
//         const DexOracle = await ethers.getContractFactory("DexPriceOracle");
//         this.dexOracle = await DexOracle.deploy();
//         await this.dexOracle.deployed();
//         await this.dexOracle.functions.setUniswapForkSourceForAsset("0x6e84a6216ea6dacc71ee8e6b0a5b7322eebc0fdd", process.env.UNISWAP_FACTORY);

//         const Oracle = await ethers.getContractFactory("PriceOracle");
//         this.oracle = await Oracle.deploy(
//             this.dexOracle.address,
//             process.env.WNATIVE
//         );
//         await this.oracle.deployed();
//         await this.oracle.functions.setAssetsSources(
//             tokens.map(({ asset }) => asset),
//             tokens.map(({ source }) => source),
//             tokens.map(({ isUSD }) => isUSD),
//         );
//         this.signers = await ethers.getSigners();
//         this.user = this.signers[0];
//     })
//     it("should be possible to create a pool", async function () {
//         const Pool = await ethers.getContractFactory("Pool");
//         this.pool = await Pool.deploy(
//             process.env.WNATIVE,
//             this.oracle.address,
//             poolConfig.collateralF.toString(),
//             poolConfig.liquidationF.toString(),
//             poolConfig.treasuryF.toString(),
//             poolConfig.maxLiq.toString(),
//             poolConfig.baseRate.toString(),
//             poolConfig.slope1.toString(),
//             poolConfig.slope2.toString(),
//             poolConfig.optimalU.toString(),
//             this.signers[0].address,
//             this.signers[0].address
//         )
//         await this.pool.deployed();
//         expect(this.pool.address).to.not.be.null;
//         await this.pool.functions.grantRole(utils.id("ADMIN_ROLE"), this.user.address);
//         // await this.pool.functions.grantRole(utils.id("DELEGATOR_ROLE"), this.user.address);

//     });
//     it(".underlying() should returns the underlying's address", async function () {
//         const res = await this.pool.functions.underlying();
//         expect(res[0]).to.be.equal(process.env.WNATIVE);
//     });
//     it(".oracle() should return the oracle's address", async function () {
//         const res = await this.pool.functions.oracle();
//         expect(res[0]).to.be.equal(this.oracle.address);
//     })
//     it(".lendingConfig() should return the lendingConfig", async function () {
//         const res = await this.pool.functions.lendingConfig();
//         expect(res[0].eq(BigNumber.from(poolConfig.collateralF.toString()))).to.be.true;
//         expect(res[1].eq(BigNumber.from(poolConfig.liquidationF.toString()))).to.be.true;
//         expect(res[2].eq(BigNumber.from(poolConfig.treasuryF.toString()))).to.be.true;
//         expect(res[3].eq(BigNumber.from(poolConfig.graceF.toString()))).to.be.true;
//     });
//     it(".interestRateConfig() should return the interestRateConfig", async function () {
//         const res = await this.pool.functions.interestRateConfig();
//         expect(res[0].eq(BigNumber.from(poolConfig.baseRate.toString()))).to.be.true;
//         expect(res[1].eq(BigNumber.from(poolConfig.slope1.toString()))).to.be.true;
//         expect(res[2].eq(BigNumber.from(poolConfig.slope2.toString()))).to.be.true;
//         expect(res[3].eq(BigNumber.from(poolConfig.optimalU.toString()))).to.be.true;
//     });
//     it(".treasuryAddress() should return the treasuryAddress", async function () {
//         const res = await this.pool.functions.treasuryAddress();
//         expect(res[0]).to.be.equal(this.signers[0].address);

//     });
//     it(".totalBorrows() should return the totalBorrows", async function () {
//         const res = await this.pool.functions.totalBorrows();
//         expect(res[0]).to.be.equal(0);
//     });
//     it(".getCash() should return the balance of the pool", async function () {
//         const res = await this.pool.functions.getCash();
//         expect(res[0]).to.be.equal(0);
//     });
//     // // ADMIN METHODS
//     it(".setOracle() should update the oracle address & emit event", async function () {
//         const Oracle = await ethers.getContractFactory("PriceOracle");
//         const oracle = await Oracle.deploy(
//             this.dexOracle.address,
//             process.env.WNATIVE
//         );
//         await oracle.deployed();
//         await this.pool.functions.setOracle(oracle.address);
//         const res = await this.pool.functions.oracle();
//         expect(res[0]).to.be.equal(oracle.address);
//         await expect(this.pool.functions.setOracle(oracle.address)).to.emit(this.pool, "OracleUpdate").withArgs(oracle.address);
//     });
//     it(".setLendingVars() should update the lending vars & emit event", async function () {
//         const newVars = [
//             (0.9 * 1e18).toString(),
//             (0.07 * 1e18).toString(),
//             (0.15 * 1e18).toString(),
//             (0.01 * 1e18).toString(),
//         ]
//         await this.pool.functions.setLendingVars(...newVars);
//         const res = await this.pool.functions.lendingConfig();
//         newVars.map((v, i) => {
//             expect(res[i].eq(BigNumber.from(v))).to.be.true;
//         })
//         await expect(this.pool.functions.setLendingVars(...newVars)).to.emit(this.pool, "LendingVarsUpdate").withArgs(...newVars);


//     });
//     it(".setInterestRateVars() should update the interest rate vars & emit event", async function () {
//         const newVars = [
//             (0).toString(),
//             (0.8 * 1e18).toString(),
//             (250 * 1e18).toString(),
//             (0.8 * 1e18).toString(),
//         ]
//         await this.pool.functions.setInterestRateVars(...newVars);
//         const res = await this.pool.functions.interestRateConfig();
//         newVars.map((v, i) => {
//             expect(res[i].eq(BigNumber.from(v))).to.be.true;
//         })
//         await expect(this.pool.functions.setInterestRateVars(...newVars)).to.emit(this.pool, "InterestRateVarsUpdate").withArgs(...newVars);
//     });

//     it(".setRewardsMananger() should update storage and emit event", async function() {
//         const Manager = await ethers.getContractFactory("RewardsManager");
//         const manager = await Manager.deploy(this.pool.address);
//         await manager.deployed()
//         const tx = await this.pool.functions.setRewardsManager(manager.address);
//         const receipt = await tx.wait()
//         const event = receipt.events.find(e => e.event == "RewardsManagerUpdate");
//         expect(event).to.not.be.undefined;
//         expect(event.args[0]).to.be.equal(manager.address);
//         const res = await this.pool.functions.rewardsManager();
//         expect(res[0]).to.be.equal(manager.address);
//     })
// });
