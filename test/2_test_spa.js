const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber, utils, constants } = require("ethers");

const tiersData = [
    {
        feeReduction: `${.25 * 1e18}`,
        minLock: 3600 * 24 * 90, // 90 days
        ratio: 1
    },
    {
        feeReduction: `${.5 * 1e18}`,
        minLock: 3600 * 24 * 365, // 1 year
        ratio: 5
    },
    {
        feeReduction: `${1e18}`,
        minLock: 3600 * 24 * 365 * 2, // 2 years
        ratio: 10
    },
]


describe("Spa", function () {
    before(async function () {
        this.signers = await ethers.getSigners();
        this.user = this.signers[0]
        this.treasury = this.signers[this.signers.length - 1]

        const ERC20 = await ethers.getContractFactory("MaxSupplyMintBurnERC20");
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

        await Promise.all(tiersData.map(async (t, i) => {
            await this.SOUL.functions.updateTierConfig(i, Object.values(t))
        }))

        await this.BODY.functions.updateSpa(this.SOUL.address);
    })

    // it(".updateTierConfig() should set the tier data and emit a TierConfigUpdate event", async function() {
    //     const tx = await this.SOUL.functions.updateTierConfig(0, Object.values(tiersData[0]))
    //     const receipt = await tx.wait()
    //     const event = receipt.events.find(e => e.event == "TierConfigUpdate");
    //     expect(event).to.not.be.undefined;
    //     console.log(event)
    //     // expect(event.args[0]).to.be.equal(0)
    // })

    it(".zenGarden() should return the zenGarden address", async function () {
        const res = await this.SOUL.functions.zenGarden()
        expect(res[0]).to.be.equal(this.BODY.address)
    })

    it(".treasury() should return the treasury address", async function () {
        const res = await this.SOUL.functions.treasury()
        expect(res[0]).to.be.equal(this.treasury.address)
    })

    it(".tierConfig() should return the tier config", async function () {
        const res = await this.SOUL.functions.tierConfig(0)
        expect(res[0].length).to.be.equal(3)
        expect(res[0][0].eq(BigNumber.from(tiersData[0].feeReduction))).to.be.true
        expect(res[0][1].eq(BigNumber.from(tiersData[0].minLock))).to.be.true
        expect(res[0][2].eq(BigNumber.from(tiersData[0].ratio))).to.be.true
    })

    it(".join() should pull BODY, mint SOUL based on the tier config and emit a Join event", async function () {
        const signer = this.signers[1];
        const zenGarden = new ethers.Contract(this.BODY.address, this.BODY.interface, signer);
        const spa = new ethers.Contract(this.SOUL.address, this.SOUL.interface, signer)
        await zenGarden.functions.approve(this.SOUL.address, `${1e20}`)

        const BODYBalanceBefore = await this.BODY.functions.balanceOf(signer.address)
        const SOULBalanceBefore = await this.SOUL.functions.balanceOf(signer.address)

        const tx = await spa.functions.join(constants.WeiPerEther, tiersData[0].minLock)
        const receipt = await tx.wait()

        const BODYBalanceAfter = await this.BODY.functions.balanceOf(signer.address)
        const SOULBalanceAfter = await this.SOUL.functions.balanceOf(signer.address)

        expect(BODYBalanceAfter[0].add(constants.WeiPerEther).eq(BODYBalanceBefore[0])).to.be.true
        expect(SOULBalanceBefore[0].eq(BigNumber.from(0))).to.be.true
        expect(SOULBalanceAfter[0].eq(
            BigNumber.from(tiersData[0].ratio).mul(constants.WeiPerEther)
        )).to.be.true

        const event = receipt.events.find(e => e.event == "Join")
        expect(event).to.not.be.undefined
        expect(event.args[0]).to.be.equal(signer.address)
    })

    it(".accountData() should return data regarding the account", async function () {
        const accountData = await this.SOUL.functions.accountData(this.signers[1].address)
        expect(accountData[0].length).to.be.equal(3)
        expect(accountData[0][0]).to.equal(0)
        expect(accountData[0][1].eq(constants.WeiPerEther)).to.be.true
        expect(accountData[0][2]).to.not.be.undefined
    })

    it(".prolongLock() should extend the lock period, adjust the tier and mint SOUL if necessary and emit a ProlongLock event", async function () {
        const signer = this.signers[1];
        const spa = new ethers.Contract(this.SOUL.address, this.SOUL.interface, signer)

        const SOULBalanceBefore = await this.SOUL.functions.balanceOf(signer.address)
        const accountDataBefore = await this.SOUL.functions.accountData(this.signers[1].address)

        const tx = await spa.functions.prolongLock(tiersData[2].minLock)
        const receipt = await tx.wait()

        const SOULBalanceAfter = await this.SOUL.functions.balanceOf(signer.address)
        const accountDataAfter = await this.SOUL.functions.accountData(this.signers[1].address)

        // check time extension
        expect(accountDataAfter[0][2].sub(accountDataBefore[0][2]).eq(BigNumber.from(tiersData[2].minLock))).to.be.true
        // check tier change
        expect(accountDataAfter[0][0]).to.be.equal(2);
        // check more SOUL has been minted due to tier change
        expect(SOULBalanceAfter[0].gt(SOULBalanceBefore[0])).to.be.true
        // check amount unchanged
        expect(accountDataAfter[0][1].eq(accountDataBefore[0][1])).to.be.true

        const event = receipt.events.find(e => e.event == "ProlongLock")
        expect(event).to.not.be.undefined;
        expect(event.args[0]).to.be.equal(signer.address)
        expect(event.args[1].eq(accountDataAfter[0][2])).to.be.true
    })

    it(".deposit() should pull BODY, mint more SOUL and emit a Deposit event", async function () {
        const signer = this.signers[1];
        const spa = new ethers.Contract(this.SOUL.address, this.SOUL.interface, signer)

        const BODYBalanceBefore = await this.BODY.functions.balanceOf(signer.address)
        const SOULBalanceBefore = await this.SOUL.functions.balanceOf(signer.address)

        const tx = await spa.functions.deposit(constants.WeiPerEther)
        const receipt = await tx.wait()

        const BODYBalanceAfter = await this.BODY.functions.balanceOf(signer.address)
        const SOULBalanceAfter = await this.SOUL.functions.balanceOf(signer.address)

        expect(BODYBalanceAfter[0].add(constants.WeiPerEther).eq(BODYBalanceBefore[0])).to.be.true
        expect(SOULBalanceAfter[0].sub(constants.WeiPerEther.mul(tiersData[2].ratio)).eq(SOULBalanceBefore[0])).to.be.true

        const event = receipt.events.find(e => e.event == "Deposit")
        expect(event).to.not.be.undefined
        expect(event.args[0]).to.be.equal(signer.address)
        expect(event.args[1].eq(constants.WeiPerEther)).to.be.true
    })

    it(".withdrawalPenalty() sould return a number", async function () {
        const signer = this.signers[1];
        const spa = new ethers.Contract(this.SOUL.address, this.SOUL.interface, signer)

        const penalty = await spa.functions.withdrawalPenalty()
        const accountData = await this.SOUL.functions.accountData(this.signers[1].address)

        // max penalty due to having prolonged earlier
        const expected = accountData[0][1].mul(BigNumber.from(`${.5 * 1e18}`)).div(constants.WeiPerEther)
        expect(penalty[0].eq(expected)).to.be.true
    })

    it(".forceWithdraw() should burn SOUL and transfer BODY to account and treasury and update amounts on ZenGarden", async function () {
        const signer = this.signers[1];
        const spa = new ethers.Contract(this.SOUL.address, this.SOUL.interface, signer)

        const SOULBalanceBefore = await this.SOUL.functions.balanceOf(signer.address)
        const BODYBalanceBefore = await this.BODY.functions.balanceOf(signer.address)
        const treasuryBODYBalanceBefore = await this.BODY.functions.balanceOf(this.treasury.address)
        const signerDepositedAmountBefore = await this.BODY.functions.depositedAmount(signer.address)
        const treasuryDepositedAmountBefore = await this.BODY.functions.depositedAmount(this.treasury.address)

        await spa.functions.forceWithdraw()

        const SOULBalanceAfter = await this.SOUL.functions.balanceOf(signer.address)
        const BODYBalanceAfter = await this.BODY.functions.balanceOf(signer.address)
        const treasuryBODYBalanceAfter = await this.BODY.functions.balanceOf(this.treasury.address)
        const signerDepositedAmountAfter = await this.BODY.functions.depositedAmount(signer.address)
        const treasuryDepositedAmountAfter = await this.BODY.functions.depositedAmount(this.treasury.address)

        const accountDataAfter = await this.SOUL.functions.accountData(this.signers[1].address)

        // check SOUL has been burned
        expect(SOULBalanceBefore[0].gt(constants.Zero)).to.be.true
        expect(SOULBalanceAfter[0].eq(constants.Zero)).to.be.true
        // ceck the account has no remaining amount deposited
        expect(accountDataAfter[0][1].eq(constants.Zero)).to.be.true
        // check signer received less than its original deposit
        expect(BODYBalanceAfter[0].eq(
            BODYBalanceBefore[0].add(treasuryBODYBalanceAfter[0].sub(treasuryBODYBalanceBefore[0]))
        )).to.be.true
        // check treasury received penalty
        expect(treasuryBODYBalanceAfter[0].gt(treasuryBODYBalanceBefore[0])).to.be.true
        expect(treasuryDepositedAmountAfter[0].sub(
            signerDepositedAmountBefore[0].sub(signerDepositedAmountAfter[0])
        ).eq(treasuryDepositedAmountBefore[0])).to.be.true

    })


})
