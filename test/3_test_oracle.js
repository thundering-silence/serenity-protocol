const { expect } = require("chai");
const { constants } = require("ethers");
const { ethers } = require("hardhat");

require('dotenv').config()

const tokens = [
    {
        // SPELL
        asset: "0xce1bffbd5374dac86a2893119683f4911a2f7814",
        source: "0x4F3ddF9378a4865cf4f28BE51E10AECb83B7daeE",
        isUSD: true
    },
    {
        // JOE
        asset: "0x6e84a6216ea6dacc71ee8e6b0a5b7322eebc0fdd",
        source: "0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a",
        isUSD: true
    },
    {
        // BTC.e
        asset: "0x50b7545627a5162f82a992c33b87adc75187b218",
        source: "0x2779D32d5166BAaa2B2b658333bA7e6Ec0C65743",
        isUSD: true
    },

]

describe("PriceOracle", function () {
    before(async function () {
        const Oracle = await ethers.getContractFactory("PriceOracle");
        this.oracle = await Oracle.deploy(
            process.env.WNATIVE
        );
        await this.oracle.deployed();
    })

    it(".getFallbackOracle() should return fallback oracle address", async function () {
        const res = await this.oracle.functions.getFallbackOracle();
        expect(res[0]).to.be.equal(constants.AddressZero);
    });

    it(".setAssetSource() should allow to set the price source for an asset", async function () {
        let errorRaised = false;
        try {
            await this.oracle.functions.setAssetSource(
                process.env.WNATIVE,
                process.env.CHAINLINK_WNATIVE_AGGREGATOR,
                true,
            );
        } catch (e) {
            errorRaised = true;
        }
        expect(errorRaised).to.be.false;
    });

    it(".setAssetSource() should only be allowed to the owner", async function () {
        const signers = await ethers.getSigners();
        let contractAsNotOwner = this.oracle.connect(signers[1]);
        let errorRaised = false;
        try {
            await contractAsNotOwner.functions.setAssetSource(
                process.env.WNATIVE,
                process.env.CHAINLINK_WNATIVE_AGGREGATOR,
                true,
            );
        } catch (e) {
            errorRaised = true;
        }
        expect(errorRaised).to.be.true;
    });

    it(".getAssetSource() should return the correct price source for the asset", async function () {
        const res = await this.oracle.functions.getAssetSource(process.env.WNATIVE);
        expect(res[0]).to.be.equal(process.env.CHAINLINK_WNATIVE_AGGREGATOR);
    });

    it(".getAssetPrice() should return a value", async function () {
        await this.oracle.functions.setAssetSource(
            process.env.USDC,
            '0xF096872672F44d6EBA71458D74fe67F9a77a23B9', // Chainlink aggregator for USDC/USD
            true,
        );
        // await this.dexOracle.functions.setUniswapForkSourceForAsset(process.env.USDC, process.env.UNISWAP_FACTORY);
        const res = await this.oracle.functions.getAssetPrice(process.env.USDC);
        expect(Number(res[0])).to.be.greaterThan(0);
    });

    // it(".getAssetPrice() should return a value even when no aggregator is set", async function () {
    //     // using JOE address here
    //     await this.dexOracle.functions.setUniswapForkSourceForAsset("0x6e84a6216ea6dacc71ee8e6b0a5b7322eebc0fdd", process.env.UNISWAP_FACTORY);
    //     const res = await this.oracle.functions.getAssetPrice("0x6e84a6216ea6dacc71ee8e6b0a5b7322eebc0fdd");
    //     expect(Number(res[0])).to.be.greaterThan(0);
    // });

    it(".setAssetsSources() should allow to set multiples sources for assets at one", async function () {

        let errorRaised = false;
        try {
            await this.oracle.functions.setAssetsSources(
                tokens.map(({ asset }) => asset),
                tokens.map(({ source }) => source),
                tokens.map(({ isUSD }) => isUSD),
            );
        } catch (e) {
            errorRaised = true;
        }
        expect(errorRaised).to.be.false;
        expect((await this.oracle.functions.getAssetSource(tokens[0].asset))[0]).to.be.equal(tokens[0].source)
        expect((await this.oracle.functions.getAssetSource(tokens[1].asset))[0]).to.be.equal(tokens[1].source)
        expect((await this.oracle.functions.getAssetSource(tokens[2].asset))[0]).to.be.equal(tokens[2].source)

    });

    it(".getAssetsPrices() should return a list of non 0 values", async function () {
        const res = await this.oracle.functions.getAssetsPrices(tokens.map(({ asset }) => asset));
        res[0].map(value => expect(Number(value)).to.be.greaterThan(0));

    });

});
