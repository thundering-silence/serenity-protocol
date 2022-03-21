// const { expect } = require("chai");
// const { ethers } = require("hardhat");
// const { BigNumber, utils } = require("ethers");

// const routerABI = require('./utils/uniRouter.abi.json').abi;

// const poolConfig = {
//     collateralF: 0.75 * 1e18,
//     liquidationF: .1 * 1e18,
//     treasuryF: 0.2 * 1e18,
//     maxLiq: .95 * 1e18,
//     flashFee: 0.00008 * 1e18,
//     baseRate: 0,
//     slope1: .07 * 1e18,
//     slope2: 3 * 1e18,
//     optimalU: .65 * 1e18,
// }


// describe("Pool - User interaction", function () {
//     before(async function () {
//         this.signers = await ethers.getSigners();
//         this.user = this.signers[0]

//         // Tokens
//         const ERC20 = await ethers.getContractFactory("MaxSupplyMintBurnERC20");
//         this.mockWrappedNative = await ERC20.deploy("WNATIVE", "NATIVE", 0);
//         this.token_2 = await ERC20.deploy("TKN2", "TKN2", 0);
//         await this.mockWrappedNative.deployed();
//         await this.mockWrappedNative.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address);
//         await this.mockWrappedNative.functions.mint(this.user.address, `${300 * 1e18}`);
//         await this.token_2.deployed();
//         await this.token_2.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address);
//         await this.token_2.functions.mint(this.user.address, `${500 * 1e18}`);

//         // Router
//         this.unirouter = new ethers.Contract("0x60aE616a2155Ee3d9A68541Ba4544862310933d4", routerABI, this.user);
//         await this.mockWrappedNative.functions.increaseAllowance(this.unirouter.address, `${90 * 1e18}`);
//         await this.token_2.functions.increaseAllowance(this.unirouter.address, `${450 * 1e18}`);
//         await this.unirouter.addLiquidity(
//             this.mockWrappedNative.address,
//             this.token_2.address,
//             `${90 * 1e18}`,
//             `${450 * 1e18}`,
//             0,
//             0,
//             this.user.address,
//             Math.ceil(Date.now() / 1000 + 300)
//         )
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
//             BigNumber.from(`${poolConfig.maxLiq}`),
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

//         // RewardsManager
//         const Manager = await ethers.getContractFactory("RewardsManager");
//         this.manager = await Manager.deploy(this.pool.address);
//         await this.manager.deployed()
//         await this.pool.functions.setRewardsManager(this.manager.address);
//         await this.token_2.functions.mint(this.user.address, `${999 * 1e18}`);
//         await this.token_2.functions.increaseAllowance(this.manager.address, `${100 * 1e18}`);
//         await this.manager.functions.setRewardConfig(this.token_2.address, `${.2*1e18}`, parseInt(Date.now() / 1000)+ 300)
//         await this.manager.activateReward(this.token_2.address)

//     })
//     it(".isCollateral() should read storage", async function () {
//         const res = await this.pool.functions.isCollateral(this.user.address);
//         expect(res[0]).to.be.equal(false);
//     })
//     it(".setCollateral() should update storage & emit event", async function () {
//         await this.pool.functions.setCollateral(true)
//         const res = await this.pool.functions.isCollateral(this.user.address);
//         expect(res[0]).to.be.equal(true);
//         await expect(this.pool.functions.setCollateral(true)).to.emit(this.pool, "SetCollateral").withArgs(this.user.address, true);
//     })
//     it(".accountDepositValue() should return the account's deposit value", async function () {
//         const res = await this.pool.functions.accountDepositValue(this.user.address);
//         expect(res[0].eq(BigNumber.from(0))).to.be.true;
//     });
//     it(".deposit() should update storage and be reflected in .accountDepositValue()", async function () {
//         await this.mockWrappedNative.functions.increaseAllowance(this.pool.address, `${1e18}`);
//         await this.pool.functions.deposit(this.user.address, `${1e18}`);
//         const res = await this.pool.functions.accountDepositValue(this.user.address);
//         expect(res[0].eq(BigNumber.from(`${5 * 1e18}`))).to.be.true;
//         const res1 = await this.mockWrappedNative.functions.balanceOf(this.pool.address);
//         expect(res1[0].eq(BigNumber.from(`${1e18}`))).to.be.true;
//     });
//     it(".accountCollateralValue() should return the account's deposit value in $USD or 0", async function () {
//         const res = await this.pool.functions.accountCollateralValue(this.user.address);
//         expect(res[0].eq(BigNumber.from(`${5 * 1e18}`))).to.be.true;
//         await this.pool.setCollateral(false);
//         const res1 = await this.pool.functions.accountCollateralValue(this.user.address);
//         expect(res1[0].eq(BigNumber.from(0))).to.be.true;
//     })
//     it(".accountMaxDebtValue() should return the account's collateral value multiplied by the collateral factor", async function () {
//         const res = await this.pool.functions.accountMaxDebtValue(this.user.address);
//         expect(res[0].eq(BigNumber.from(0))).to.be.true;
//         await this.pool.setCollateral(true);
//         const res1 = await this.pool.functions.accountMaxDebtValue(this.user.address);
//         expect(res1[0].eq(BigNumber.from(`${poolConfig.collateralF * 5}`)))
//     })
//     it(".borrow() should fail if asking more than cash", async function () {
//         let errorRaised = false;
//         try {
//             const cash = await this.pool.functions.getCash();
//             await this.pool.functions.borrow(this.user.address, `${cash[0] + 1}`);
//         } catch (e) {
//             errorRaised = true;
//         }
//         expect(errorRaised).to.be.true;
//     });
//     it(".borrow() should transfer value to account", async function () {
//         const beforeBorrow = await this.mockWrappedNative.functions.balanceOf(this.user.address);
//         await this.pool.functions.borrow(this.user.address, `${5 * 1e17}`);
//         const afterBorrow = await this.mockWrappedNative.functions.balanceOf(this.user.address);
//         expect(afterBorrow[0].eq(beforeBorrow[0].add(BigNumber.from(`${5 * 1e17}`)))).to.be.true;
//     });
//     it(".accountDebtValue() should update storage and return the debt value for the account", async function () {
//         const debtValueAfterBorrow1 = await this.pool.functions.accountDebtValue(this.user.address);
//         // 5 times the amount borrowed as 1 mockNative = $5
//         expect(debtValueAfterBorrow1[0].gte(BigNumber.from(`${5 * 5 * 1e17}`))).to.be.true;
//         await this.pool.functions.borrow(this.user.address, `${2 * 1e17}`);
//         const debtValueAfterBorrow2 = await this.pool.functions.accountDebtValue(this.user.address);
//         // 5 times the amount borrowed as 1 mockNative = $5
//         expect(debtValueAfterBorrow2[0].gt(BigNumber.from(`${5 * 7 * 1e17}`))).to.be.true;
//         await this.pool.functions.borrow(this.user.address, `${3 * 1e17}`);
//         const debtValueAfterBorrow3 = await this.pool.functions.accountDebtValue(this.user.address);
//         // 5 times the amount borrowed as 1 mockNative = $5
//         expect(debtValueAfterBorrow3[0].gt(BigNumber.from(`${5 * 10 * 1e17}`))).to.be.true;
//     })
//     it(".repay() should update storage, reduce account's debt value and transfer tokens to pool", async function () {
//         await this.mockWrappedNative.functions.increaseAllowance(this.pool.address, `${200 * 1e18}`)
//         await this.pool.functions.repay(this.user.address, `${2 * 1e17}`);

//         const debtAmountAfterRepay1 = await this.pool.functions.accountDebtAmount(this.user.address);
//         expect(debtAmountAfterRepay1[0].gt(BigNumber.from(`${7 * 1e17}`))).to.be.true;

//         await this.pool.functions.repay(this.user.address, `${2 * 1e18}`);
//         const debtAmountAfterRepay2 = await this.pool.functions.accountDebtAmount(this.user.address);
//         expect(debtAmountAfterRepay2[0].eq(BigNumber.from(0))).to.be.true;

//         const afterRepayBalance = await this.mockWrappedNative.functions.balanceOf(this.pool.address);
//         expect(afterRepayBalance[0].gt(BigNumber.from(`${1e18}`))).to.be.true;
//     })
//     it(".withdraw() should update storage and transfer tokens back to the depositor", async function () {
//         const totalDepositBeforeWithdraw = await this.pool.functions.accountDepositAmount(this.user.address);
//         expect(totalDepositBeforeWithdraw[0].eq(BigNumber.from(`${1e18}`))).to.be.true;

//         await this.pool.functions.withdraw(this.user.address, `${1e18}`);
//         // total Deposit not yet updated with interest on contract
//         const totalDepositaAfterWithdraw1 = await this.pool.functions.accountDepositAmount(this.user.address);
//         expect(totalDepositaAfterWithdraw1[0].gt(BigNumber.from(0))).to.be.true;

//         await this.pool.functions.withdraw(this.user.address, `${1e18}`);
//         const totalDepositaAfterWithdraw2 = await this.pool.functions.accountDepositAmount(this.user.address);
//         expect(totalDepositaAfterWithdraw2[0].eq(BigNumber.from(0))).to.be.true;

//         const afterRepayBalance = await this.mockWrappedNative.functions.balanceOf(this.user.address);
//         expect(afterRepayBalance[0].gt(BigNumber.from(`${1e18}`))).to.be.true;
//      })
// });
