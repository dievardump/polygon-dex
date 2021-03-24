const { expect } = require('chai');
const hre = require('hardhat');

const {
  BN, // Big Number support
  constants, // Common constants, like the zero address and largest integers
  expectRevert, // Assertions for transactions that should fail
} = require('@openzeppelin/test-helpers');

function expectEvent(receipt, event) {
  const found = (receipt.events || []).find((log) => log.event === event);

  if (!found) {
    throw new Error(`Event ${event} not found`);
  }

  return found;
}

describe('SimpleDex', function () {
  let simpleDex;
  let transferProxy;
  let erc721;
  let erc1155;

  let owner;
  let addr1;
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

  before(async () => {
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

    order721_OK = [
      typeERC721,
      erc721.address,
      1, // tokenId
      1, // quantity
      ethers.utils.parseEther('1.0'), // price
      constants.ZERO_ADDRESS, // buyToken, we don't support it now
      constants.ZERO_ADDRESS, // taker
      0, // maxPerBuy, can only be 1 or 0 for erc721
    ];

    // this one can only be bought by addr4
    order721_OK_TAKER = [...order721_OK];
    order721_OK_TAKER[2] = 2;
    order721_OK_TAKER[6] = addr4.address;

    // won't work because quantity is wrong
    order721_KO = [...order721_OK];
    order721_KO[2] = 3;
    order721_KO[3] = 3;

    order1155_OK = [
      typeERC1155,
      erc1155.address,
      1, // tokenId
      7, // quantity
      ethers.utils.parseEther('1.0'), // price
      constants.ZERO_ADDRESS, // buyToken, we don't support it now
      constants.ZERO_ADDRESS, // taker
      3, // maxPerBuy, can only be 1 or 0 for erc721
    ];

    order1155_KO = [...order1155_OK];
    order1155_KO[3] = 15;
  });

  it('createOrder should fail because not owner', async function () {
    await expectRevert(
      simpleDex.connect(addr3).createOrder(...order721_OK),
      'Dex: User not owner of token',
    );
  });

  it('createOrder should fail because not approved', async function () {
    await expectRevert(
      simpleDex.connect(addr2).createOrder(...order721_OK),
      'Dex: Dex not approved to transfer',
    );
  });

  it('createOrder should fail because quantity is not 1', async function () {
    await erc721.connect(addr2).setApprovalForAll(transferProxy.address, true);

    await expectRevert(
      simpleDex.connect(addr2).createOrder(...order721_KO),
      'Dex: Quantity must be 1 for ERC721',
    );
  });

  it('createOrder should not fail', async function () {
    const data = await simpleDex.connect(addr2).createOrder(...order721_OK);
    const receipt = await data.wait();

    const event = expectEvent(receipt, 'OrderCreated');
    orderId = event.args.orderId;
  });

  it('buy should fail because orderId does not exist', async function () {
    await expectRevert(
      simpleDex
        .connect(addr4)
        .buy(
          '0x73121498972aec2676fcdd627b5c58bc31e8fecc5d5ce924973971718bdd52aa',
          1,
        ),
      'Dex: Order not currently open',
    );
  });

  it('buy should fail to buy because amount is 0', async function () {
    await expectRevert(
      simpleDex.connect(addr4).buy(orderId, 0),
      'Dex: quantity must be > 0',
    );
  });

  it('buy should fail because value not right', async function () {
    await expectRevert(
      simpleDex.connect(addr4).buy(orderId, 1),
      'Dex: Sent value is incorrect',
    );
  });

  it('buy should be ok', async function () {
    const nftOwner = await erc721.ownerOf(order721_OK[2]);
    expect(nftOwner.toString()).to.be.equal(addr2.address);

    const value = calcValue(order721_OK);

    const data = await simpleDex.connect(addr4).buy(orderId, 1, {
      value,
    });

    const receipt = await data.wait();

    expectEvent(receipt, 'Buy');
    expectEvent(receipt, 'OrderClosed');

    const nftOwnerAfter = await erc721.ownerOf(order721_OK[2]);
    expect(nftOwnerAfter.toString()).to.be.equal(addr4.address);
  });

  it('buy should fail for same orderId when erc721', async function () {
    const value = calcValue(order721_OK);
    await expectRevert(
      simpleDex.connect(addr4).buy(orderId, 1, {
        value,
      }),
      'Dex: Order not currently open',
    );
  });

  it('buy should fail when not Taker', async function () {
    const data = await simpleDex
      .connect(addr2)
      .createOrder(...order721_OK_TAKER);
    const receipt = await data.wait();

    const event = expectEvent(receipt, 'OrderCreated');
    orderId = event.args.orderId;

    const value = calcValue(order721_OK_TAKER);
    await expectRevert(
      simpleDex.connect(addr3).buy(orderId, 1, {
        value,
      }),
      'Dex: Order not for this user',
    );
  });

  it('buy should be ok when Taker', async function () {
    const nftOwner = await erc721.ownerOf(order721_OK_TAKER[2]);
    expect(nftOwner.toString()).to.be.equal(addr2.address);

    const value = calcValue(order721_OK_TAKER);

    const data = await simpleDex.connect(addr4).buy(orderId, 1, {
      value,
    });

    const receipt = await data.wait();

    expectEvent(receipt, 'Buy');
    expectEvent(receipt, 'OrderClosed');

    const nftOwnerAfter = await erc721.ownerOf(order721_OK_TAKER[2]);
    expect(nftOwnerAfter.toString()).to.be.equal(addr4.address);
  });

  it('createOrder should fail for 1155 because balance too small', async function () {
    // create Order
    await expectRevert(
      simpleDex.connect(addr2).createOrder(...order1155_KO),

      'Dex: User has not enough balance',
    );
  });

  it('createOrder should fail for 1155 because not approved', async function () {
    // create Order
    await expectRevert(
      simpleDex.connect(addr2).createOrder(...order1155_OK),

      'Dex: Dex not approved to transfer',
    );
  });

  it('createOrder should be ok for 1155', async function () {
    // setApprovalForAll
    await erc1155.connect(addr2).setApprovalForAll(transferProxy.address, true);

    const data = await simpleDex.connect(addr2).createOrder(...order1155_OK);
    const receipt = await data.wait();

    const event = expectEvent(receipt, 'OrderCreated');
    orderId = event.args.orderId;
  });

  it('buy should be ok for 1155', async function () {
    const quantity = 3;
    const balanceBefore = await erc1155.balanceOf(
      addr4.address,
      order1155_OK[2],
    );

    const value = calcValue(order1155_OK, quantity);
    const data = await simpleDex.connect(addr4).buy(orderId, quantity, {
      value,
    });

    const receipt = await data.wait();
    expectEvent(receipt, 'Buy');

    const balanceAfter = await erc1155.balanceOf(
      addr4.address,
      order1155_OK[2],
    );
    expect(balanceAfter.sub(balanceBefore).valueOf()).to.be.equal(quantity);
  });

  it('buy should be ok again for 1155', async function () {
    const quantity = 3;
    const balanceBefore = await erc1155.balanceOf(
      addr4.address,
      order1155_OK[2],
    );

    const value = calcValue(order1155_OK, quantity);
    const data = await simpleDex.connect(addr4).buy(orderId, quantity, {
      value,
    });

    const receipt = await data.wait();
    expectEvent(receipt, 'Buy');

    const balanceAfter = await erc1155.balanceOf(
      addr4.address,
      order1155_OK[2],
    );
    expect(balanceAfter.sub(balanceBefore).valueOf()).to.be.equal(quantity);
  });

  it('buy should be fail ecause not enough are remaining', async function () {
    const quantity = 3;
    const value = calcValue(order1155_OK, quantity);
    await expectRevert(
      simpleDex.connect(addr4).buy(orderId, quantity, {
        value,
      }),
      'Dex: not enough remaining.',
    );
  });

  it('buy should be ok and close the 1155 order', async function () {
    const quantity = 1;
    const balanceBefore = await erc1155.balanceOf(
      addr4.address,
      order1155_OK[2],
    );

    const value = calcValue(order1155_OK, quantity);
    const data = await simpleDex.connect(addr4).buy(orderId, quantity, {
      value,
    });

    const receipt = await data.wait();
    expectEvent(receipt, 'Buy');
    expectEvent(receipt, 'OrderClosed');

    const balanceAfter = await erc1155.balanceOf(
      addr4.address,
      order1155_OK[2],
    );
    expect(balanceAfter.sub(balanceBefore).valueOf()).to.be.equal(quantity);
  });
});
