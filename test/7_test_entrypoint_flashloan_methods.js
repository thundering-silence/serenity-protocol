const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber, constants, utils } = require("ethers");

require('dotenv').config();


describe("EntryPoint flash loans logic", function () {
    before(async function () {
        this.signers = await ethers.getSigners();
        this.user = this.signers[0]
        this.treasury = this.signers[this.signers.length - 1]

        // Tokens
        const ERC20 = await ethers.getContractFactory("MaxSupplyMintBurnERC20");
        this.mockWrappedNative = await ERC20.deploy("WNATIVE", "NATIVE", 0);
        this.token = await ERC20.deploy("LINK", "LINK", 0);
        await this.mockWrappedNative.deployed();
        await this.mockWrappedNative.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address);
        await this.mockWrappedNative.functions.mint(this.user.address, `${100 * 1e18}`);
        await this.token.deployed();
        await this.token.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address);
        await this.token.functions.mint(this.user.address, `${500 * 1e18}`);

        // PriceOracle
        const Oracle = await ethers.getContractFactory("PriceOracle");
        this.oracle = await Oracle.deploy(
            this.mockWrappedNative.address
        );
        await this.oracle.deployed();
        await this.oracle.functions.setAssetSource(
            this.mockWrappedNative.address,
            process.env.CHAINLINK_WNATIVE_AGGREGATOR,
            true,
        );
        await this.oracle.functions.setAssetSource(
            this.token.address,
            process.env.CHAINLINK_LINK_AGGREGATOR,
            true,
        );

        this.MIND = await ERC20.deploy("MIND", "Mind", 0);
        await this.MIND.deployed();
        await this.MIND.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address)
        await this.MIND.functions.grantRole(utils.id("BURNER_ROLE"), this.user.address)
        await Promise.all(this.signers.map(async (s) => {
            await this.MIND.functions.mint(s.address, `${1e20}`)
        }))
        await this.MIND.functions.burn(this.treasury.address, `${1e20}`) // reset treasury

        const ZenGarden = await ethers.getContractFactory("ZenGarden");
        this.BODY = await ZenGarden.deploy(`${this.MIND.address}`);
        await this.BODY.deployed();

        await Promise.all(this.signers.map(async s => {
            if (this.treasury.address == s.address) return;
            const mind = new ethers.Contract(this.MIND.address, this.MIND.interface, s);
            const zenGarden = new ethers.Contract(this.BODY.address, this.BODY.interface, s);
            await mind.functions.approve(this.BODY.address, `${1e20}`)
            await zenGarden.functions.enter(`${1e20}`)
        }))

        const Spa = await ethers.getContractFactory("Spa");
        this.SOUL = await Spa.deploy(this.BODY.address, this.treasury.address, constants.WeiPerEther)
        await this.SOUL.deployed()

        const FeesCollector = await ethers.getContractFactory("FeesCollector");
        this.feesCollector = await FeesCollector.deploy(
            this.treasury.address,
            this.BODY.address,
            this.user.address
        )
        await this.feesCollector.deployed()

        // Entrypoint Storage
        const EntryPointStorage = await ethers.getContractFactory("EntryPointStorage");
        this.entryPointStorage = await EntryPointStorage.deploy(
            this.SOUL.address,
            this.oracle.address,
        )
        await this.entryPointStorage.deployed();

        const EntryPoint = await ethers.getContractFactory("EntryPoint");
        this.entryPoint = await EntryPoint.deploy(
            this.entryPointStorage.address,
            constants.AddressZero
        )
        await this.entryPoint.deployed();

        const tx1 = await this.entryPointStorage.functions.createPool(
            this.mockWrappedNative.address,
            this.feesCollector.address,
            [
                `${0.75 * 1e18}`, // collateralFactor
                `${0.1 * 1e18}`, // liquidationFee
                `${0.2 * 1e18}`, // fee
                `${0.95 * 1e18}`, // maxLiquidationThreshold
                true, // allow borrowing
            ],
            [
                `${0}`, // baseRate,
                `${.07 * 1e18}`, // slope1
                `${5 * 1e18}`, // slope2
                `${.75 * 1e18}` // optimal Util
            ],
            [
                true, // activate flash loans
                `${.0008 * 1e18}`, // flashFee 0.08%
            ]
        )
        const receipt1 = await tx1.wait()
        const event1 = receipt1.events.find(e => e.event == "NewPool");
        this.nativePoolAddress = event1.args[1];
        await this.entryPointStorage.setPoolForUnderlying(this.mockWrappedNative.address, this.nativePoolAddress);

        const Pool = await ethers.getContractFactory("Pool")
        this.wrappedNativePool = new ethers.Contract(this.nativePoolAddress, Pool.interface, this.user)

        await this.wrappedNativePool.functions.grantRole(utils.id("DELEGATOR_ROLE"), this.entryPoint.address)

        await this.mockWrappedNative.functions.increaseAllowance(this.nativePoolAddress, BigNumber.from(`${10 * 1e18}`));
        await this.entryPoint.functions.deposit(this.mockWrappedNative.address, BigNumber.from(`${10 * 1e18}`));
        await this.entryPoint.functions.setCollateral(this.mockWrappedNative.address, true)

        const tx2 = await this.entryPointStorage.functions.createPool(
            this.token.address,
            this.feesCollector.address,
            [
                `${0.75 * 1e18}`, // collateralFactor
                `${0.1 * 1e18}`, // liquidationFee
                `${0.2 * 1e18}`, // fee
                `${0.95 * 1e18}`, // maxLiquidationThreshold
                true, // allow borrowing
            ],
            [
                `${0}`, // baseRate,
                `${.07 * 1e18}`, // slope1
                `${5 * 1e18}`, // slope2
                `${.75 * 1e18}` // optimal Util
            ],
            [
                false, // deactivate flash loans
                `${.0008 * 1e18}`, // flashFee 0.08%
            ]
        )
        const receipt2 = await tx2.wait();
        const event2 = receipt2.events.find(e => e.event == "NewPool")
        this.tokenPoolAddress = event2.args[1];
        await this.entryPointStorage.setPoolForUnderlying(this.token.address, this.tokenPoolAddress);
        await this.entryPointStorage.supportNewAsset(this.token.address);

        const pool = Pool.attach(this.tokenPoolAddress);
        await pool.functions.grantRole(utils.id("DELEGATOR_ROLE"), this.entryPoint.address);

        await this.token.functions.increaseAllowance(this.tokenPoolAddress, constants.WeiPerEther)
        await this.entryPoint.functions.deposit(this.token.address, constants.WeiPerEther);
        await this.entryPoint.functions.setCollateral(this.token.address, true)

        await this.entryPoint.functions.borrow(this.token.address, constants.WeiPerEther);
    })

    it(".flashFee() should return at maximum the base fee", async function() {
        const loan = constants.WeiPerEther.mul(BigNumber.from(`${1e2}`))
        const res = await this.entryPoint.functions.flashFee(this.mockWrappedNative.address, loan)
        expect(res[0].lte(BigNumber.from(`${.0008 * 1e20}`))).to.be.true
    })

    it(".maxFlashLoan() should return 0 if flashloans are disabled", async function() {
        const res = await this.entryPoint.functions.maxFlashLoan(this.token.address)
        expect(res[0].eq(constants.Zero)).to.be.true
    })

    it(".maxFlashLoan() should return the pool's cash if flashloans are enabled", async function() {
        const res = await this.entryPoint.functions.maxFlashLoan(this.mockWrappedNative.address)
        expect(res[0].gt(constants.Zero)).to.be.true
    })

    // it(".flashLoan() should let users swap their deposited assets", async function () {
    //     await this.entryPoint.functions.increaseWithdrawAllowance(this.mockWrappedNative.address, this.entryPoint.address, constants.MaxUint256);
    //     await this.entryPoint.functions.increaseWithdrawAllowance(this.token.address, this.entryPoint.address, constants.MaxUint256);
    //     await this.entryPoint.functions.increaseBorrowAllowance(this.mockWrappedNative.address, this.entryPoint.address, constants.MaxUint256);
    //     await this.entryPoint.functions.increaseBorrowAllowance(this.token.address, this.entryPoint.address, constants.MaxUint256);

    //     const tx = await this.entryPoint.functions.flashLoan([
    //         BigNumber.from(1),
    //         this.entryPoint.address,
    //         this.mockWrappedNative.address,
    //         constants.WeiPerEther.div(BigNumber.from(5)),
    //         this.user.address,
    //         this.token.address,
    //         constants.Zero,
    //     ])
    //     const receipt = await tx.wait()
    // })

    // it(".repay() should reduce debt and emit a 'Repay' event", async function () {
    //     await this.token.functions.increaseAllowance(this.tokenPoolAddress, `${10 * 1e18}`)

    //     const feesCollectorBalanceBefore = await this.token.functions.balanceOf(this.feesCollector.address)
    //     expect(feesCollectorBalanceBefore[0].eq(constants.Zero)).to.be.true

    //     const tx = await this.entryPoint.functions.repay(this.token.address, `${1 * 1e1}`);
    //     const receipt = await tx.wait();

    //     const event = receipt.events.find(e => e.event == "Repay");
    //     expect(event).to.not.be.undefined;
    //     expect(event.args[0]).to.be.equal(this.user.address)
    //     expect(event.args[1]).to.be.equal(this.token.address)
    //     expect(event.args[2]).to.be.equal(`${1 * 1e1}`)

    //     const debtInfo = await this.entryPointStorage.functions.accountOverallPosition(this.user.address, false);
    //     expect(debtInfo[0].gt(BigNumber.from(constants.WeiPerEther))).to.be.true;
    //     await this.entryPoint.functions.repay(this.token.address, `${2 * 1e18}`);

    //     const debtInfoAfterRepay = await this.entryPointStorage.functions.accountOverallPosition(this.user.address, false);
    //     expect(debtInfoAfterRepay[0].eq(constants.Zero)).to.be.true;

    //     const feesCollectorBalanceAfter = await this.token.functions.balanceOf(this.feesCollector.address)
    //     expect(feesCollectorBalanceAfter[0].gt(constants.Zero)).to.be.true

    // })

    // it(".withdraw() should allow to withdraw funds and emit an event", async function () {
    //     const tx = await this.entryPoint.functions.withdraw(this.mockWrappedNative.address, `${10 * 1e18}`)
    //     const receipt = await tx.wait();
    //     const event = receipt.events.find(e => e.event == "Withdraw")
    //     expect(event).to.not.be.undefined;
    //     expect(event.args[0]).to.be.equal(this.user.address)
    //     expect(event.args[1]).to.be.equal(this.mockWrappedNative.address)
    //     // Amount withdrawn is the same as the deposited as no one borrowed this asset while deposited, so no yield :(
    //     expect(event.args[2].eq(BigNumber.from(`${10 * 1e18}`))).to.be.true;
    // })

});
