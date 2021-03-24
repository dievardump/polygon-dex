// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require('hardhat');
// scripts/create-box.js
const { ethers, upgrades } = require('hardhat');

async function main() {
  // We get the contract to deploy
  const TransferProxy = await ethers.getContractFactory('TransferProxy');
  const SimpleDex = await ethers.getContractFactory('SimpleDex');

  // Deploy transferProxy, this will set caller as the Owner
  const transferProxy = await upgrades.deployProxy(TransferProxy, []);
  await transferProxy.deployed();
  console.log('TransferProxy deployed to:', transferProxy.address);

  // deploy Sale contract
  const simpleDex = await upgrades.deployProxy(SimpleDex, [
    process.env.SERVICE_FEE_BENEFICIARY,
    transferProxy.address,
    process.env.SERVICE_FEE || 0,
  ]);
  await simpleDex.deployed();
  console.log('Dex contract deployed to:', simpleDex.address);

  // add contract as operators on the TransferProxy
  await transferProxy.addOperators([simpleDex.address]);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
