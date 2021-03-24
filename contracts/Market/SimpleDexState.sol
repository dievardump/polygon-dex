// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol';
import '../Proxys/Transfer/ITransferProxy.sol';

abstract contract SimpleDexState {
  event Buy(
    bytes32 indexed orderId, /* orderId */
    address indexed token, /* nft registry address */
    uint256 indexed tokenId, /* tokenId of the nft */
    uint256 amount, /* amount that was bought */
    address maker, /* maker of the order */
    address taker, /* taker of the order */
    uint256 value, /* full value of the tx */
    address buyToken, /* the token used to buy */
    uint256 serviceFee /* part going to service fees */
  );

  // fired when an order is created
  event OrderCreated(
    address indexed maker,
    address indexed token,
    uint256 indexed tokenId,
    uint256 quantity,
    bytes32 orderId,
    address taker /* if order is for a specific address */
  );

  // fired when an order is closed
  event OrderClosed(
    bytes32 indexed orderId,
    address indexed token,
    uint256 indexed tokenId,
    address operator /* who closed the order - used to determine if it was canceled or closed on buy */
  );

  enum TokenType {ERC1155, ERC721}

  struct OrderData {
    /* tokenType */
    TokenType tokenType;
    /* maker of the order */
    address maker;
    /* taker of the order */
    address taker;
    /* Token contract  */
    address token;
    /* TokenId */
    uint256 tokenId;
    /* Quantity for this order */
    uint256 quantity;
    /* Max items by each buy. Allow to create one big order, but to limit how many can be bought at once */
    uint256 maxPerBuy;
    /* OrderNonce so we can have different order for the same tokenId */
    uint256 makerNonce;
    /* Buy token */
    address buyToken; /* address(0) for current chain native token */
    /* Unit price */
    uint256 unitPrice;
    /* total order value; only used in contract */
    uint256 total;
    /* total value for seller; only used in contract */
    uint256 endValue;
  }

  uint256 public serviceFee;
  address payable public beneficiary;
  ITransferProxy public transferProxy;

  // contains a list of all orders still open
  EnumerableSetUpgradeable.Bytes32Set internal _openOrders;

  // user nonce since orders are stored in the contract we need a nonce for each order
  mapping(address => uint256) internal _makerNonces;

  // all orders
  mapping(bytes32 => OrderData) public orders;
  mapping(bytes32 => uint256) internal _completed;
}
