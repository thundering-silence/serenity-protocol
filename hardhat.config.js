require("dotenv").config();

require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("hardhat-gas-reporter");
require("solidity-coverage");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 100,
          }
        }
      },{
        version: "0.4.0"
      }
    ]
  },
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {
      gasPrice: 225000000000,
      chainId: 43114,
      forking: {
        url: 'https://api.avax.network/ext/bc/C/rpc',
        enabled: true,
        accounts:
          process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      }
    },
    // fuji: {
    //   gasPrice: 225000000000,
    //   chainId: 43114,
    //   forking: {
    //     url: "https://api.avax-test.network/ext/bc/C/rpc",
    //     accounts:
    //       process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    //   }
    // },
    ropsten: {
      url: process.env.ROPSTEN_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};
