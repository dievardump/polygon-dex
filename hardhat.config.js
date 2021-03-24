require('@nomiclabs/hardhat-ethers');
require('@nomiclabs/hardhat-web3');
require('@nomiclabs/hardhat-waffle');
require('@openzeppelin/hardhat-upgrades');
require('hardhat-tracer');

require('dotenv').config();

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: '0.7.3',
  networks: {
    polygon: {
      url: process.env.POLYGON_PROVIDER,
      gasPrice: 1000000000,
      accounts: [process.env.DEPLOYER_PKEY],
    },
  },
};
