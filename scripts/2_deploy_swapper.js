const { ethers } = require('hardhat');
const { utils, BigNumber } = require('ethers');
const fs = require('fs')

require('dotenv').config()

const uniForks = [
    {
        name: 'Trader Joe',
        address: '0x60aE616a2155Ee3d9A68541Ba4544862310933d4'
    },
    {
        name: 'SushiSwap',
        address: '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506'
    },
    {
        name: 'Pangolin',
        address: '0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106'
    },
    {
        name: 'Lydia',
        address: '0xA52aBE4676dbfd04Df42eF7755F01A3c41f28D27'
    },
    {
        name: 'HakuSwap',
        address: '0x5F1FdcA239362c5b8A8Ada26a256ac5626CC33E0'
    }
]

const pairs = [
    {
        in: '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7', // WAVAX
        out: '0x49d5c2bdffac6ce2bfdb6640f4f80f226bc10bab'// WETH.e
    },
    {
        in: '0x6e84a6216ea6dacc71ee8e6b0a5b7322eebc0fdd',// JOE
        out: '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7' // WAVAX
    },
    {
        in: '0xa32608e873f9ddef944b24798db69d80bbb4d1ed',// CRA
        out: '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7'// WAVAX
    }
]


async function main() {
    const Swapper = await ethers.getContractFactory("Swapper");
    const swapper = await Swapper.deploy();
    console.log(`Swapper deployed at: ${swapper.address}`)
    fs.appendFileSync('.env', `SWAPPER=${swapper.address}\n`);
    await Promise.all(uniForks.map(async ({name, address}) => await swapper.createOrUpdateRouter(
        utils.formatBytes32String(name),
        address
    )))
    // const res = await Promise.all(pairs.map(async p => await swapper.getBestSwap(p.in, BigNumber.from(`${1e18}`), p.out)))
    // console.log(res)
}


main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
