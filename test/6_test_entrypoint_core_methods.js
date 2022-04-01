const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber, constants, utils } = require("ethers");

require('dotenv').config();


describe("EntryPoint core logic", function () {
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

        const Thermae = await ethers.getContractFactory("Thermae");
        this.SOUL = await Thermae.deploy(this.BODY.address, this.treasury.address, constants.WeiPerEther)
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

        const tx = await this.entryPointStorage.functions.createPool(
            this.mockWrappedNative.address,
            this.feesCollector.address,
            [
                `${0.75 * 1e18}`, // collateralFactor
                `${0.1 * 1e18}`, // liquidationFee
                `${0.95 * 1e18}`, // maxLiquidationThreshold
                `${0.2 * 1e18}`, // fee
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
        const receipt = await tx.wait()
        const event = receipt.events.find(e => e.event == "NewPool");
        this.nativePoolAddress = event.args[1];
        await this.entryPointStorage.setPoolForUnderlying(this.mockWrappedNative.address, this.nativePoolAddress);

        const Pool = await ethers.getContractFactory("Pool")
        this.pool = new ethers.Contract(this.nativePoolAddress, Pool.interface, this.user)

        await this.pool.functions.grantRole(utils.id("DELEGATOR_ROLE"), this.entryPoint.address)
    })

    it(".deposit() should update account's markets and emit a 'Deposit' event", async function () {
        await this.mockWrappedNative.functions.increaseAllowance(this.nativePoolAddress, BigNumber.from(`${10 * 1e18}`));
        const tx = await this.entryPoint.functions.deposit(this.mockWrappedNative.address, BigNumber.from(`${10 * 1e18}`));
        const receipt = await tx.wait()
        const event = receipt.events.find(e => e.event == "Deposit");
        expect(event).to.not.be.undefined;
        expect(event.args[0]).to.be.equal(this.user.address)
        expect(event.args[1]).to.be.equal(this.mockWrappedNative.address)
        expect(event.args[2]).to.be.equal(`${10 * 1e18}`)
        const res = await this.entryPointStorage.functions.isAccountInMarket(this.user.address, this.nativePoolAddress);
        expect(res[0]).to.be.true;
    })

    it(".borrow() should revert if there is no pool for the asset", async function () {
        let errorRaised = false
        try {
            await this.entryPoint.functions.borrow(this.token.address, constants.WeiPerEther);
        } catch (e) {
            errorRaised = `${e}`.includes('No Pool for asset');
        }
        expect(errorRaised).to.be.true;
    })

    it(".borrow() should revert if no deposits are set as collateral", async function () {
        const tx = await this.entryPointStorage.functions.createPool(
            this.token.address,
            this.feesCollector.address,
            [
                `${0.75 * 1e18}`, // collateralFactor
                `${0.1 * 1e18}`, // liquidationFee
                `${0.95 * 1e18}`, // maxLiquidationThreshold
                `${0.2 * 1e18}`, // fee
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
        const receipt = await tx.wait();
        const event = receipt.events.find(e => e.event == "NewPool")
        this.tokenPoolAddress = event.args[1];
        await this.entryPointStorage.setPoolForUnderlying(this.token.address, this.tokenPoolAddress);
        await this.entryPointStorage.supportNewAsset(this.token.address);

        const Pool = await ethers.getContractFactory("Pool");
        const pool = Pool.attach(this.tokenPoolAddress);
        await pool.functions.grantRole(utils.id("DELEGATOR_ROLE"), this.entryPoint.address);

        let errorRaised = false
        try {
            await this.entryPoint.functions.borrow(this.token.address, 1);
        } catch (e) {
            errorRaised = true;
        }
        expect(errorRaised).to.be.true;
    })

    it(".borrow() should revert if loan is too big", async function () {
        let errorRaised = false
        try {
            await this.entryPoint.functions.borrow(this.mockWrappedNative.address, constants.WeiPerEther);
        } catch (e) {
            errorRaised = `${e}`.includes('Borrow: Liquidation threshold reached');
        }
        expect(errorRaised).to.be.true;
    })

    it(".borrow() should revert if there is not enough cash to borrow", async function () {
        await this.entryPoint.functions.setCollateral(this.mockWrappedNative.address, true);
        let errorRaised = false
        try {
            await this.entryPoint.functions.borrow(this.token.address, constants.WeiPerEther);
        } catch (e) {
            errorRaised = `${e}`.includes("No more liquidity to borrow");
        }
        expect(errorRaised).to.be.true;
    })

    it(".borrow() should transfer tokens when conditions are met and emit a 'Borrow' event", async function () {
        await this.token.functions.increaseAllowance(this.tokenPoolAddress, constants.WeiPerEther)
        await this.entryPoint.functions.deposit(this.token.address, constants.WeiPerEther);
        let errorRaised = false
        const beforeBorrow = await this.token.functions.balanceOf(this.user.address);
        let event;
        try {
            const tx = await this.entryPoint.functions.borrow(this.token.address, constants.WeiPerEther);
            receipt = await tx.wait()
            event = receipt.events.find(e => e.event == "Borrow")
        } catch (e) {
            console.log(e)
            errorRaised = true
        }
        expect(errorRaised).to.be.false;
        const afterBorrow = await this.token.functions.balanceOf(this.user.address);
        expect(afterBorrow[0].eq(beforeBorrow[0].add(BigNumber.from(constants.WeiPerEther))));
        expect(event).to.not.be.undefined;
        expect(event.args[0]).to.be.equal(this.user.address);
        expect(event.args[1]).to.be.equal(this.token.address);
        expect(event.args[2]).to.be.equal(constants.WeiPerEther);
    })

    it(".withdraw() should not be allowed when it puts account at risk of liquidation", async function () {
        let errorRaised = false;
        try {
            await this.entryPoint.functions.withdraw(this.mockWrappedNative.address, `${10 * 1e18}`)
        } catch (e) {
            errorRaised = `${e}`.includes("Withdraw: Liquidation threshold reached");
        }
        expect(errorRaised).to.be.true;
    })

    it(".repay() should reduce debt and emit a 'Repay' event", async function () {
        await this.token.functions.increaseAllowance(this.tokenPoolAddress, `${10 * 1e18}`)

        const feesCollectorBalanceBefore = await this.token.functions.balanceOf(this.feesCollector.address)
        expect(feesCollectorBalanceBefore[0].eq(constants.Zero)).to.be.true

        const tx = await this.entryPoint.functions.repay(this.token.address, `${1 * 1e1}`);
        const receipt = await tx.wait();

        const event = receipt.events.find(e => e.event == "Repay");
        expect(event).to.not.be.undefined;
        expect(event.args[0]).to.be.equal(this.user.address)
        expect(event.args[1]).to.be.equal(this.token.address)
        expect(event.args[2]).to.be.equal(`${1 * 1e1}`)

        const debtInfo = await this.entryPointStorage.functions.accountOverallPosition(this.user.address, false);
        expect(debtInfo[0].gt(BigNumber.from(constants.WeiPerEther))).to.be.true;
        await this.entryPoint.functions.repay(this.token.address, `${2 * 1e18}`);

        const debtInfoAfterRepay = await this.entryPointStorage.functions.accountOverallPosition(this.user.address, false);
        expect(debtInfoAfterRepay[0].eq(constants.Zero)).to.be.true;

        const feesCollectorBalanceAfter = await this.token.functions.balanceOf(this.feesCollector.address)
        expect(feesCollectorBalanceAfter[0].gt(constants.Zero)).to.be.true

    })

    it(".withdraw() should allow to withdraw funds and emit an event", async function () {
        const tx = await this.entryPoint.functions.withdraw(this.mockWrappedNative.address, `${10 * 1e18}`)
        const receipt = await tx.wait();
        const event = receipt.events.find(e => e.event == "Withdraw")
        expect(event).to.not.be.undefined;
        expect(event.args[0]).to.be.equal(this.user.address)
        expect(event.args[1]).to.be.equal(this.mockWrappedNative.address)
        // Amount withdrawn is the same as the deposited as no one borrowed this asset while deposited, so no yield :(
        expect(event.args[2].eq(BigNumber.from(`${10 * 1e18}`))).to.be.true;
    })

});
