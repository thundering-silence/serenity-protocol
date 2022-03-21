const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber, constants, utils } = require("ethers");

const routerABI = require('./utils/uniRouter.abi.json').abi;

const poolConfig = {
    collateralF: 0.75 * 1e18,
    liquidationF: .1 * 1e18,
    treasuryF: 0.2 * 1e18,
    maxLiq: .95 * 1e18,
    baseRate: 0,
    slope1: .07 * 1e18,
    slope2: 3 * 1e18,
    optimalU: .65 * 1e18,
}


describe("EntryPointStorage", function () {
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

        // Mock aggregator
        const MockAggregatorV3 = await ethers.getContractFactory("MockAggregatorV3");
        const mockAggr = await MockAggregatorV3.deploy();
        await mockAggr.deployed();
        await mockAggr.functions.setAnswer(`${5 * 1e8}`);

        // PriceOracle
        const Oracle = await ethers.getContractFactory("PriceOracle");
        this.oracle = await Oracle.deploy(
            this.mockWrappedNative.address
        );
        await this.oracle.deployed();
        await this.oracle.functions.setAssetSource(
            this.mockWrappedNative.address,
            mockAggr.address,
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
    })
    it(".oracle() shoudl return the oracle set when deploying", async function () {
        const res = await this.entryPointStorage.functions.oracle();
        expect(res[0]).to.be.equal(this.oracle.address);
    })

    it(".createPool() should create a new pool and emit an event", async function () {
        const tx = await this.entryPointStorage.functions.createPool(
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
                false, // activate flash loans
                `${0}`, // flashFee
            ]
        )
        const receipt = await tx.wait()
        const event = receipt.events.find(e => e.event == "NewPool");
        expect(event).to.not.be.undefined;
        expect(event.args[0]).to.be.equal(this.mockWrappedNative.address)
        expect(event.args[1]).to.not.be.equal(constants.AddressZero)
    });

    it(".setPoolForUnderlying() should update storage and it's value should be returned by .poolForUnderlying()", async function () {
        const tx = await this.entryPointStorage.functions.createPool(
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
        const receipt = await tx.wait()
        const event = receipt.events.find(e => e.event == "NewPool");
        this.nativePoolAddress = event.args[1];
        await this.entryPointStorage.setPoolForUnderlying(this.mockWrappedNative.address, this.nativePoolAddress);
        const res = await this.entryPointStorage.functions.poolForUnderlying(this.mockWrappedNative.address);
        expect(res[0]).to.be.equal(this.nativePoolAddress);
    })

    it(".poolForUnderlying() should return the correct pool", async function () {
        const res = await this.entryPointStorage.poolForUnderlying(this.mockWrappedNative.address);
        expect(res[0]).to.not.be.equal(constants.AddressZero);
    })

    it(".supportNewAsset() should update storage", async function () {
        await this.entryPointStorage.functions.supportNewAsset(this.mockWrappedNative.address);
        const res = await this.entryPointStorage.functions.supportedAssets();
        expect(res[0].length).to.be.equal(1);
    })

    it(".supportedAssets() should return a list of supported assets", async function () {
        const res = await this.entryPointStorage.functions.supportedAssets();
        expect(res[0].length).to.be.equal(1);
    })

    it(".removeSupportForAsset() should update storage", async function () {
        await this.entryPointStorage.functions.removeSupportForAsset(this.mockWrappedNative.address);
        const res = await this.entryPointStorage.functions.supportedAssets();
        expect(res[0].length).to.be.equal(0);
    })

    it(".isAccountInMarket() should return wether a account is a specific market", async function () {
        const res = await this.entryPointStorage.functions.isAccountInMarket(this.user.address, this.nativePoolAddress);
        expect(res[0]).to.be.false;
    })

    it(".accountMarkets() should return the markets the account is in", async function () {
        const res = await this.entryPointStorage.functions.accountMarkets(this.user.address);
        expect(res[0].length).to.be.equal(0);
    })

    it(".accountOverallPosition() should return three values", async function () {
        const res = await this.entryPointStorage.functions.accountOverallPosition(this.user.address, false);
        expect(res[0].eq(BigNumber.from(0))).to.be.true;
        expect(res[1].eq(BigNumber.from(0))).to.be.true;
        expect(res[2]).to.be.false;
    })
});
