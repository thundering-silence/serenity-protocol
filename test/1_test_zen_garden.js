const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber, utils } = require("ethers");



describe("ZenGarden", function () {
    before(async function () {
        this.signers = await ethers.getSigners();
        this.user = this.signers[0]

        const ERC20 = await ethers.getContractFactory("MaxSupplyMintBurnERC20");
        this.MIND = await ERC20.deploy("MIND", "Mind", 0);
        await this.MIND.deployed();

        const ZenGarden = await ethers.getContractFactory("ZenGarden");
        this.BODY = await ZenGarden.deploy(`${this.MIND.address}`);
        await this.BODY.deployed();

        await this.MIND.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address)

        await Promise.all(this.signers.map(async (s, i) => {
            await this.MIND.functions.mint(s.address, `${(i + 1) * 1e18}`)
        }))

        await this.MIND.functions.mint(this.user.address, `${1e20}`)

    })

    it("contructor should set MIND at deployment", async function () {
        const mind = await this.BODY.functions.mind();
        expect(mind[0]).to.be.equal(this.MIND.address);
    })

    it(".addReward() should update state and emit a RewardActivated event", async function () {
        const tx = await this.BODY.functions.addReward(this.MIND.address);
        const receipt = await tx.wait()
        const event = receipt.events.find(e => e.event == "RewardActivated")
        expect(event).to.not.be.undefined;
        expect(event.args[0]).to.be.equal(this.MIND.address)
    })

    it(".rewards() should return a list of addresses", async function () {
        const res = await this.BODY.functions.rewards();
        expect(res[0].length).to.be.equal(1)
        expect(res[0][0]).to.be.equal(this.MIND.address)
    })

    it(".enter() should pull MIND, mint BODY and emit a Enter event", async function () {
        await this.MIND.functions.approve(this.BODY.address, `${1e18}`)
        const MindBalalnceBefore = await this.MIND.functions.balanceOf(this.user.address)
        const tx = await this.BODY.functions.enter(`${5 * 1e17}`)
        const receipt = await tx.wait()

        const BODYBalance = await this.BODY.functions.balanceOf(this.user.address)
        expect(BODYBalance[0].eq(BigNumber.from(`${5 * 1e17}`))).to.be.true

        const MINDBalanceAfter = await this.MIND.functions.balanceOf(this.user.address)

        expect((MindBalalnceBefore[0].sub(MINDBalanceAfter[0])).eq(BigNumber.from(`${5 * 1e17}`))).to.be.true;

        const event = receipt.events.find(e => e.event == "Enter")
        expect(event).to.not.be.undefined
        expect(event.args[0]).to.be.equal(this.user.address)
        expect(event.args[1]).to.be.equal(`${5 * 1e17}`)
    })

    it(".depositReward() should update state and emit a Deposit event", async function () {
        await this.MIND.functions.approve(this.BODY.address, `${1e18}`)
        const tx = await this.BODY.depositReward(this.MIND.address, `${1e18}`)
        const receipt = await tx.wait()
        const event = receipt.events.find(e => e.event == "Deposit")
        expect(event).to.not.be.undefined;
        expect(event.args[0]).to.be.equal(this.MIND.address)
        expect(event.args[1]).to.be.equal(`${1e18}`)
    })

    it(".claimableAmount() should return the claimable amount per reward", async function () {
        // the only staker should take all
        const res = await this.BODY.functions.claimableAmount(this.MIND.address);
        expect(res[0].eq(BigNumber.from(`${1e18}`)))
    })

    it(".pauseReward() should set the reward as paused, emit a RewardPaused event and prevent additional deposits", async function () {
        const tx = await this.BODY.functions.pauseReward(this.MIND.address);
        const receipt = await tx.wait()
        const event = receipt.events.find(e => e.event == "RewardPaused")
        expect(event).to.not.be.undefined
        expect(event.args[0]).to.be.equal(this.MIND.address)

        let errorRaised = false;
        try {
            await this.BODY.functions.depositReward(this.MIND.address, 1);
        } catch (e) {
            errorRaised = `${e}`.includes("REWARD is PAUSED")
        }
        expect(errorRaised).to.be.true

    })

    it(".unpauseReward() should set the reward as no longer paused and emit a RewardUnpaused event", async function () {
        const tx = await this.BODY.functions.unpauseReward(this.MIND.address);
        const receipt = await tx.wait()
        const event = receipt.events.find(e => e.event == "RewardUnpaused")
        expect(event).to.not.be.undefined
        expect(event.args[0]).to.be.equal(this.MIND.address)
    })

    it(".depositReward() should fairly distribute the reward to all stakers", async function () {
        await Promise.all(this.signers.map(async (s, i) => {
            const mind = new ethers.Contract(this.MIND.address, this.MIND.interface, s);
            const zenGarden = new ethers.Contract(this.BODY.address, this.BODY.interface, s);
            await mind.functions.approve(this.BODY.address, `${1e18}`)
            await zenGarden.functions.enter(`${i == 0 ? 5 * 1e17 : 1e18}`)
        }))

        await this.MIND.functions.approve(this.BODY.address, `${1e20}`)
        await this.BODY.functions.depositReward(this.MIND.address, `${1e20}`)

        const expectedReward = BigNumber.from(`${1e20}`).div(BigNumber.from(this.signers.length));

        const claimableAmounts = await Promise.all(this.signers.map(async (s, i) => {
            const zenGarden = new ethers.Contract(this.BODY.address, this.BODY.interface, s);
            const res = await zenGarden.functions.claimableAmount(this.MIND.address)
            return res[0]
        }))

        claimableAmounts.map(a => expect(a.eq(expectedReward)).to.be.true)
    })

    it(".claim() should claim a reward and emit a Claim event", async function () {
        const tx = await this.BODY.functions.claim(this.MIND.address)
        const receipt = await tx.wait()
        const event = receipt.events.find(e => e.event == "Claim")
        expect(event).to.not.be.undefined
        expect(event.args[0]).to.be.equal(this.user.address)
        expect(event.args[1]).to.be.equal(this.MIND.address)
        expect(event.args[2]).to.be.equal(`${5 * 1e18}`);

        const claimable = await this.BODY.functions.claimableAmount(this.MIND.address)
        expect(claimable[0].eq(BigNumber.from(0))).to.be.true
    })

    it(".multiClaim() should claim multiple rewards ", async function () {
        const ERC20 = await ethers.getContractFactory("MaxSupplyMintBurnERC20");
        const TKN = await ERC20.deploy("TKN", "TKN", 0);
        await TKN.deployed();
        await TKN.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address)
        await TKN.functions.mint(this.user.address, `${1e18}`)

        await this.MIND.functions.approve(this.BODY.address, `${1e20}`)
        await this.BODY.functions.depositReward(this.MIND.address, `${1e18}`)

        await this.BODY.functions.addReward(TKN.address)
        await TKN.functions.approve(this.BODY.address, `${1e18}`)
        await this.BODY.functions.depositReward(TKN.address, `${1e18}`)

        const MINDBalanceBefore = await this.MIND.functions.balanceOf(this.user.address)
        const TKNBalanceBefore = await TKN.functions.balanceOf(this.user.address)

        await this.BODY.multiClaim([this.MIND.address, TKN.address])

        const MINDBalanceAfter = await this.MIND.functions.balanceOf(this.user.address)
        const TKNBalanceAfter = await TKN.functions.balanceOf(this.user.address)

        expect((MINDBalanceAfter[0].gt(MINDBalanceBefore[0])))
        expect((TKNBalanceAfter[0].gt(TKNBalanceBefore[0])))
    })

    it(".transfer() should claim rewards for both sender and receiver and transfer to receiver ", async function () {

        const senderData = {
            signer: this.signers[1],
            claimableBefore: null,
            claimableAfter: null,
            balanceBefore: null,
            balanceAfter: null
        }
        const receiverData = {
            signer: this.signers[2],
            claimableBefore: null,
            claimableAfter: null,
            balanceBefore: null,
            balanceAfter: null
        };

        const zenGardenSender = new ethers.Contract(this.BODY.address, this.BODY.interface, senderData.signer);
        const zenGardenReceiver = new ethers.Contract(this.BODY.address, this.BODY.interface, receiverData.signer);
        const zero = BigNumber.from(0)

        senderData.claimableBefore = await zenGardenSender.functions.claimableAmount(this.MIND.address)
        receiverData.claimableBefore = await zenGardenReceiver.functions.claimableAmount(this.MIND.address)

        expect(senderData.claimableBefore[0].gt(zero)).to.be.true
        expect(receiverData.claimableBefore[0].gt(zero)).to.be.true

        senderData.balanceBefore = await this.MIND.functions.balanceOf(senderData.signer.address)
        receiverData.balanceBefore = await this.MIND.functions.balanceOf(receiverData.signer.address)

        await zenGardenSender.functions.transfer(receiverData.signer.address, `${1e18}`)

        senderData.claimableAfter = await zenGardenSender.functions.claimableAmount(this.MIND.address)
        receiverData.claimableAfter = await zenGardenReceiver.functions.claimableAmount(this.MIND.address)

        expect(senderData.claimableAfter[0].eq(zero)).to.be.true
        expect(receiverData.claimableAfter[0].eq(zero)).to.be.true

        senderData.balanceAfter = await this.MIND.functions.balanceOf(senderData.signer.address)
        receiverData.balanceAfter = await this.MIND.functions.balanceOf(receiverData.signer.address)

        expect((senderData.balanceAfter[0].sub(senderData.balanceBefore[0])).eq(senderData.claimableBefore[0])).to.be.true
        expect((receiverData.balanceAfter[0].sub(receiverData.balanceBefore[0])).eq(receiverData.claimableBefore[0])).to.be.true

    })

    it(".exit() should claim rewards, burn BODY, send MIND and emit a Exit event", async function () {
        await this.MIND.functions.approve(this.BODY.address, `${1e20}`)
        await this.BODY.functions.depositReward(this.MIND.address, `${1e17}`)

        const BODYbalanceBefore = await this.BODY.functions.balanceOf(this.user.address)
        const MINDBalanceBefore = await this.MIND.functions.balanceOf(this.user.address)

        const claimableMINDAmount = await this.BODY.functions.claimableAmount(this.MIND.address)

        const tx = await this.BODY.functions.exit(BODYbalanceBefore[0])
        const receipt = await tx.wait()

        // only MIND is still claimable as TKN has a claimable reward of 0
        const claimEvent = receipt.events.find(e => e.event == "Claim")
        expect(claimEvent).to.not.be.undefined
        expect(claimEvent.args[1]).to.be.equal(this.MIND.address)

        const BODYbalanceAfter = await this.BODY.functions.balanceOf(this.user.address)
        expect(BODYbalanceAfter[0].eq(BigNumber.from(0))).to.be.true

        const MINDBalanceAfter = await this.MIND.functions.balanceOf(this.user.address)

        expect((MINDBalanceBefore[0].add(BODYbalanceBefore[0].add(claimableMINDAmount[0])).eq(MINDBalanceAfter[0]))).to.be.true
     })

     it(".removeReward() should remove the reward, set the reward per share to 0 and emit a RewardRemoved event", async function () {
        await this.BODY.functions.enter(`${1e18}`)

        await this.MIND.functions.approve(this.BODY.address, `${1e20}`)
        await this.BODY.functions.depositReward(this.MIND.address, `${1e10}`)

        const claimableAmountBefore = await this.BODY.functions.claimableAmount(this.MIND.address)
        expect(claimableAmountBefore[0].gt(BigNumber.from(0))).to.be.true

        const tx = await this.BODY.functions.removeReward(this.MIND.address)
        const receipt = await tx.wait()

        const rewards = await this.BODY.functions.rewards()
        expect(rewards[0].length).to.be.equal(1)

        const claimableAmountAfter = await this.BODY.functions.claimableAmount(this.MIND.address)
        expect(claimableAmountAfter[0].eq(BigNumber.from(0))).to.be.true

        const event = receipt.events.find(e => e.event == "RewardRemoved")
        expect(event).to.not.be.undefined
        expect(event.args[0]).to.be.equal(this.MIND.address)
    })

})
