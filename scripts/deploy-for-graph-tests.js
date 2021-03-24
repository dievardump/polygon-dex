const hre = require('hardhat');
// scripts/create-box.js
const { ethers, upgrades } = require('hardhat');

const {
  constants, // Common constants, like the zero address and largest integers
} = require('@openzeppelin/test-helpers');

function expectEvent(receipt, event) {
  const found = (receipt.events || []).find((log) => log.event === event);

  if (!found) {
    throw new Error(`Event ${event} not found`);
  }

  return found;
}

async function main() {
  let simpleDex;
  let transferProxy;
  let erc721;
  let erc1155;

  let addr2;
  let addr3;

  let typeERC721;
  let typeERC1155;

  let order721_OK;
  let order721_OK_TAKER;

  let order721_KO;

  let order1155_OK;
  let order1155_KO;

  let orderId;

  let serviceFee;

  function toBN(value) {
    return ethers.BigNumber.from(value);
  }

  function calcValue(order, quantity = 1) {
    const bnValue = toBN(order[4]).mul(toBN(quantity));
    const fees = bnValue.mul(toBN(serviceFee)).div(toBN(10000));

    return bnValue.add(fees);
  }

  [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();

  // We get the contract to deploy
  const SimpleDex = await ethers.getContractFactory('SimpleDex');
  const TransferProxy = await ethers.getContractFactory('TransferProxy');

  // mocks
  const ERC721Dummy = await ethers.getContractFactory('ERC721Dummy');
  const ERC1155Dummy = await ethers.getContractFactory('ERC1155Dummy');

  // Deploy transferProxy, this will set caller as the Owner
  transferProxy = await upgrades.deployProxy(TransferProxy, []);
  await transferProxy.deployed();

  // deploy SimpleDex contract
  simpleDex = await upgrades.deployProxy(SimpleDex, [
    addr3.address,
    transferProxy.address,
    250,
  ]);

  await simpleDex.deployed();

  // add contract as operators on the TransferProxy
  await transferProxy.addOperators([simpleDex.address]);

  serviceFee = await simpleDex.serviceFee();

  erc721 = await ERC721Dummy.connect(addr2).deploy();
  erc1155 = await ERC1155Dummy.connect(addr2).deploy();

  typeERC1155 = 0;
  typeERC721 = 1;

  await erc721.connect(addr2).setApprovalForAll(transferProxy.address, true);
  await erc1155.connect(addr2).setApprovalForAll(transferProxy.address, true);

  let erc721TokenId = 10;
  let erc1155TokenId = 10;
  async function doERC721() {
    erc721TokenId++;

    // create item
    await erc721.connect(addr2).mint(erc721TokenId);

    // create order for item
    const orderData = [
      typeERC721,
      erc721.address,
      erc721TokenId, // tokenId
      1, // quantity
      ethers.utils.parseEther('1.0'), // price
      constants.ZERO_ADDRESS, // buyToken, we don't support it now
      constants.ZERO_ADDRESS, // taker
      0, // maxPerBuy, can only be 1 or 0 for erc721
    ];

    const data = await simpleDex.connect(addr2).createOrder(...orderData);
    const receipt = await data.wait();
    const event = expectEvent(receipt, 'OrderCreated');
    orderId = event.args.orderId;

    // fulfill order
    const value = calcValue(orderData);
    await simpleDex.connect(addr4).buy(orderId, 1, {
      value,
    });
  }

  async function doERC1155() {
    erc1155TokenId++;

    // create item
    await erc1155.connect(addr2).mint(erc1155TokenId);

    const orderData = [
      typeERC1155,
      erc1155.address,
      erc1155TokenId, // tokenId
      7, // quantity
      ethers.utils.parseEther('1.0'), // price
      constants.ZERO_ADDRESS, // buyToken, we don't support it now
      constants.ZERO_ADDRESS, // taker
      3, // maxPerBuy, can only be 1 or 0 for erc721
    ];

    const data = await simpleDex.connect(addr2).createOrder(...orderData);
    const receipt = await data.wait();
    const event = expectEvent(receipt, 'OrderCreated');
    orderId = event.args.orderId;

    // fulfill order
    let value = calcValue(orderData, 3);
    await simpleDex.connect(addr4).buy(orderId, 3, {
      value,
    });

    value = calcValue(orderData, 3);
    await simpleDex.connect(addr4).buy(orderId, 3, {
      value,
    });

    value = calcValue(orderData, 1);
    await simpleDex.connect(addr4).buy(orderId, 1, {
      value,
    });
  }

  for (let i = 0; i < 5; i++) {
    await doERC721();
    await doERC1155();
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
