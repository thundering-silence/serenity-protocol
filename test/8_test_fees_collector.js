const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber, constants, utils } = require("ethers");

require('dotenv').config();


describe("FeesCollector", function () {
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
        await this.mockWrappedNative.functions.mint(
            this.user.address,
            BigNumber.from(`${1e9}`).mul(constants.WeiPerEther)
        );
        await this.token.deployed();
        await this.token.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address);
        await this.token.functions.mint(
            this.user.address,
            BigNumber.from(`${1e9}`).mul(constants.WeiPerEther)
        );

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
        await this.BODY.functions.addReward(this.mockWrappedNative.address)
        await this.BODY.functions.addReward(this.token.address)

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
        // set feesColector distribution params
        await this.feesCollector.functions.setFeeDistributionParams(
            this.wrappedNativePool.address,
            [
                `${.375 * 1e18}`,
                `${.375 * 1e18}`,
                `${.25 * 1e18}`,
                0
            ])

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
                true, // activate flash loans
                `${.0008 * 1e18}`, // flashFee 0.08%
            ]
        )
        const receipt2 = await tx2.wait();
        const event2 = receipt2.events.find(e => e.event == "NewPool")
        this.tokenPoolAddress = event2.args[1];
        await this.entryPointStorage.setPoolForUnderlying(this.token.address, this.tokenPoolAddress);
        await this.entryPointStorage.supportNewAsset(this.token.address);

        this.tokenPool = Pool.attach(this.tokenPoolAddress);
        this.tokenPool.functions.grantRole(utils.id("DELEGATOR_ROLE"), this.entryPoint.address);
        // set feesColector distribution params
        await this.feesCollector.functions.setFeeDistributionParams(
            this.tokenPool.address,
            [
                `${.375 * 1e18}`,
                `${.375 * 1e18}`,
                `${.25 * 1e18}`,
                0
            ])

        // DEPOSIT
        await this.mockWrappedNative.functions.increaseAllowance(this.nativePoolAddress, constants.WeiPerEther);
        await this.entryPoint.functions.deposit(this.mockWrappedNative.address, constants.WeiPerEther);
        await this.entryPoint.functions.setCollateral(this.mockWrappedNative.address, true)

        // BORROW
        await this.token.functions.increaseAllowance(this.tokenPoolAddress, constants.WeiPerEther)
        await this.entryPoint.functions.deposit(this.token.address, constants.WeiPerEther);
        await this.entryPoint.functions.borrow(this.token.address, constants.WeiPerEther);

        // WAIT A BIT
        await new Promise((resolve, reject) => resolve(setTimeout(() => { }, 2000)))

    })


    it("EntryPoint.repay() should transfer some of the interest to feesCollector", async function () {
        await this.token.functions.increaseAllowance(this.tokenPoolAddress, `${10 * 1e18}`)

        const feesCollectorBalanceBefore = await this.token.functions.balanceOf(this.feesCollector.address)
        expect(feesCollectorBalanceBefore[0].eq(constants.Zero)).to.be.true

        await this.entryPoint.functions.repay(this.token.address, `${1 * 1e1}`);

        await this.entryPoint.functions.repay(this.token.address, `${2 * 1e18}`);

        const feesCollectorBalanceAfter = await this.token.functions.balanceOf(this.feesCollector.address)
        expect(feesCollectorBalanceAfter[0].gt(constants.Zero)).to.be.true

    })

    it(".distribute() should follow the distribution params", async function () {
        const feesCollectorBalanceBefore = await this.token.functions.balanceOf(this.feesCollector.address)

        const treasuryBalanceBefore = await this.token.functions.balanceOf(this.treasury.address)
        const zenGardenBalanceBefore = await this.token.functions.balanceOf(this.BODY.address)
        const devBalanceBefore = await this.token.functions.balanceOf(this.user.address)

        await this.feesCollector.functions.distribute(this.tokenPool.address)

        const treasuryBalanceAfter = await this.token.functions.balanceOf(this.treasury.address)
        const zenGardenBalanceAfter = await this.token.functions.balanceOf(this.BODY.address)
        const devBalanceAfter = await this.token.functions.balanceOf(this.user.address)

        expect(treasuryBalanceAfter[0].gt(treasuryBalanceBefore[0])).to.be.true
        expect(zenGardenBalanceAfter[0].gt(zenGardenBalanceBefore[0])).to.be.true
        expect(devBalanceAfter[0].gt(devBalanceBefore[0])).to.be.true

        const expectedTreasuryBalance = feesCollectorBalanceBefore[0].mul(BigNumber.from(`${.375 * 1e18}`)).div(constants.WeiPerEther)
        const expectedZenGardenBalance = feesCollectorBalanceBefore[0].mul(BigNumber.from(`${.375 * 1e18}`)).div(constants.WeiPerEther)
        const expectedDevBalance = feesCollectorBalanceBefore[0].mul(BigNumber.from(`${.25 * 1e18}`).div(constants.WeiPerEther))
        expect(treasuryBalanceAfter[0].eq(expectedTreasuryBalance)).to.be.true
        expect(zenGardenBalanceAfter[0].eq(expectedZenGardenBalance)).to.be.true

        // console.log(devBalanceAfter[0])
        // console.log(devBalanceBefore[0].add(expectedDevBalance))
        // expect(devBalanceAfter[0].sub(expectedDevBalance).eq(devBalanceBefore[0])).to.be.true
        // expect(
        //     treasuryBalanceAfter[0].add(
        //         zenGardenBalanceAfter[0].add(devBalanceAfter[0])
        //     ).eq(feesCollectorBalanceBefore[0]
        //     )
        // ).to.be.true
    })

});
