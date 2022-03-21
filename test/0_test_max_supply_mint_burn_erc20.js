const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber, utils } = require("ethers");



describe("MaxSupplyMintableBurnableERC20", function () {
    before(async function () {
        this.signers = await ethers.getSigners();
        this.user = this.signers[0]

        const ERC20 = await ethers.getContractFactory("MaxSupplyMintBurnERC20");
        this.token = await ERC20.deploy("TKN", "TKN", `${100 * 1e18}`);
        await this.token.deployed();
    })
    it(".mint() should not allow to mint if the sender does not have the MINTER ROLE", async function () {
        let errorRaised = false;
        try {
            await this.token.functions.mint(this.user.address, `${1e18}`);
        } catch (e) {
            errorRaised = `${e}`.includes(utils.id("MINTER_ROLE"))
        }
        expect(errorRaised).to.be.true;
    })
    it(".mint() should allow to mint if the sender does have the MINTER ROLE", async function () {
        let errorRaised = false;
        try {
            await this.token.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address);
            await this.token.functions.mint(this.user.address, `${1e18}`);
        } catch (e) {
            errorRaised = true
        }
        expect(errorRaised).to.be.false;
        const res = await this.token.functions.balanceOf(this.user.address);
        expect(res[0].eq(BigNumber.from(`${1e18}`))).to.be.true;
    })
    it(".mint() should not allow to mint more than maxSupply", async function () {
        let errorRaised = false;
        try {
            await this.token.functions.grantRole(utils.id("MINTER_ROLE"), this.user.address);
            await this.token.functions.mint(this.user.address, `${100*1e18}`);
        } catch (e) {
            errorRaised = true
        }
        expect(errorRaised).to.be.false;
        const res = await this.token.functions.balanceOf(this.user.address);
        expect(res[0].eq(BigNumber.from(`${100*1e18}`))).to.be.true;
    })
    it(".burn() should not allow to burn if the sender does not have the BURNER ROLE", async function () {
        let errorRaised = false;
        try {
            await this.token.functions.burn(this.user.address, `${1e18}`);
        } catch (e) {
            errorRaised = `${e}`.includes(utils.id("BURNER_ROLE"))
        }
        expect(errorRaised).to.be.true;
    })
    it(".burn() should allow to burn if the sender does have the BURNER ROLE", async function () {
        let errorRaised = false;
        try {
            await this.token.functions.grantRole(utils.id("BURNER_ROLE"), this.user.address);
            await this.token.functions.burn(this.user.address, `${1e18}`);
        } catch (e) {
            errorRaised = true;
        }
        expect(errorRaised).to.be.false;
        const res = await this.token.functions.balanceOf(this.user.address);
        expect(res[0].eq(BigNumber.from(`${99*1e18}`))).to.be.true;
    })
})
