// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol';

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';

import '../Proxys/Transfer/ITransferProxy.sol';
import './SimpleDexState.sol';

/**
 * Never reorder the herited contracts
 * Always add at the end
 */
contract SimpleDex is
  OwnableUpgradeable,
  ReentrancyGuardUpgradeable,
  SimpleDexState
{
  using SafeMathUpgradeable for uint256;
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

  function initialize(
    address payable _beneficiary,
    address _transferProxy,
    uint256 _serviceFee
  ) public initializer {
    __Ownable_init();
    __ReentrancyGuard_init();

    setBeneficiary(_beneficiary);
    setTransferProxy(_transferProxy);
    setServiceFee(_serviceFee);
  }

  function setServiceFee(uint256 _serviceFee) public onlyOwner {
    require(_serviceFee <= 1000, 'Dex: Service fees too high');
    serviceFee = _serviceFee;
  }

  function setTransferProxy(address _transferProxy) public onlyOwner {
    require(_transferProxy != address(0));
    transferProxy = ITransferProxy(_transferProxy);
  }

  function setBeneficiary(address payable _beneficiary) public onlyOwner {
    require(_beneficiary != address(0));
    beneficiary = _beneficiary;
  }

  /**
   * @dev create an order for msgSender
   *
   * Requirement:
   * - Sender must be owner at the time of order creation
   * - Sender must have approved transferProxy to transfer
   */
  function createOrder(
    TokenType tokenType,
    address token,
    uint256 tokenId,
    uint256 quantity,
    uint256 unitPrice,
    address buyToken,
    address taker,
    uint256 maxPerBuy
  ) external returns (bytes32 orderId) {
    address maker = _msgSender();
    address proxy = address(transferProxy);

    if (tokenType == TokenType.ERC721) {
      // check that owner is maker
      require(
        IERC721(token).ownerOf(tokenId) == maker,
        'Dex: User not owner of token'
      );

      require(
        IERC721(token).isApprovedForAll(maker, proxy) ||
          IERC721(token).getApproved(tokenId) == proxy,
        'Dex: Dex not approved to transfer'
      );

      require(quantity == 1, 'Dex: Quantity must be 1 for ERC721');
    } else {
      require(
        IERC1155(token).balanceOf(maker, tokenId) >= quantity,
        'Dex: User has not enough balance'
      );

      require(
        IERC1155(token).isApprovedForAll(maker, proxy),
        'Dex: Dex not approved to transfer'
      );
    }

    uint256 makerNonce = _makerNonces[maker].add(1);

    OrderData memory order;
    order.tokenType = tokenType;
    order.makerNonce = makerNonce;
    order.maker = maker;
    order.token = token;
    order.tokenId = tokenId;
    order.quantity = quantity;
    order.unitPrice = unitPrice;
    order.buyToken = buyToken;
    order.taker = taker;
    order.maxPerBuy = maxPerBuy;

    orderId = _getOrderId(order);
    require(
      orders[orderId].maker == address(0),
      'Dex: Order id already used, please call incrementNonce() before trying again'
    );

    // update state after the last require
    _makerNonces[maker] = makerNonce;
    orders[orderId] = order;
    _openOrders.add(orderId);

    emit OrderCreated(maker, token, tokenId, quantity, orderId, taker);
  }

  /**
   * @dev function allowing a user to increment their nonce
   * This is used in the case of a duplicated orderId so user can increment their nonce
   * the orderId will then change
   */
  function incrementNonce() external {
    address maker = _msgSender();
    _makerNonces[maker] = _makerNonces[maker].add(1);
  }

  /**
   * @dev buy from an order
   *
   * Requirements:
   * - order is open
   * - taker not set or sender === taker
   * - quantity is set, so we don't have 0 value orders
   * - maxPerBuy not set or quantity < maxPerBuy
   * - quantity must be lte than the remaining amount of items to buy
   */
  function buy(
    bytes32 orderId,
    uint256 quantity // quantity to buy
  ) external payable nonReentrant {
    // verify that order is open
    require(_openOrders.contains(orderId), 'Dex: Order not currently open');

    OrderData memory order = orders[orderId];
    address sender = _msgSender();

    // verify if this order is for a specific address
    if (order.taker != address(0)) {
      require(sender == order.taker, 'Dex: Order not for this user');
    }

    // verify that quantity > 0
    require(quantity > 0, 'Dex: quantity must be > 0');

    // not max perBuy or quantity is lte
    require(
      order.maxPerBuy == 0 || quantity <= order.maxPerBuy,
      'Dex: Amount too big'
    );

    // update order state
    bool closed = _verifyOpenAndModifyState(orderId, order, quantity);

    // calculate all values (service fees, quantity for recipient, quantity for seller, ...)
    order.total = order.unitPrice.mul(quantity);
    uint256 fees = order.total.mul(serviceFee).div(10000);

    // for the moment only matic supported, but soon...
    if (order.buyToken == address(0)) {
      require(
        msg.value == order.total.add(fees), // total = (unitPrice * amount) + fees
        'Dex: Sent value is incorrect'
      );
    } else {
      // @TODO: v2 - manage erc20 here
    }

    // set endValue to total
    order.endValue = order.total;

    // send token to buyer
    if (order.tokenType == TokenType.ERC1155) {
      transferProxy.erc1155SafeTransferFrom(
        order.token,
        order.maker,
        sender,
        order.tokenId,
        quantity,
        bytes('')
      );
    } else {
      transferProxy.erc721SafeTransferFrom(
        order.token,
        order.maker,
        sender,
        order.tokenId,
        bytes('')
      );
    }

    // send service fees to beneficiary
    if (fees > 0) {
      beneficiary.transfer(fees);
    }

    // @TODO: v2 - here manage royalties when found the right way

    if (order.endValue > 0) {
      payable(order.maker).transfer(order.endValue);
    }

    // emit buy
    emit Buy(
      orderId,
      order.token,
      order.tokenId,
      quantity,
      order.maker,
      sender,
      order.total,
      order.buyToken,
      fees
    );

    // if order is closed, emit close.
    if (closed) {
      _closeOrder(orderId, order, sender);
    }
  }

  function cancelOrder(bytes32 orderId) external {
    OrderData memory order = orders[orderId];
    address sender = _msgSender();
    require(sender == order.maker, 'Dex: not your order order');

    _closeOrder(orderId, order, sender);
  }

  /**
   * @dev Returns a paginated list of open orders
   *
   * @param cursor Index to start at
   * @param perPage How many we want per page
   *
   * @return openOrders orders list
   * @return nextCursor next cursor to use
   */
  function getPaginatedOpenOrders(uint256 cursor, uint256 perPage)
    external
    view
    returns (OrderData[] memory openOrders, uint256 nextCursor)
  {
    bytes32[] memory orderIds;
    (orderIds, nextCursor) = getPaginatedOpenOrderIds(cursor, perPage);
    uint256 length = orderIds.length;

    openOrders = new OrderData[](length);
    for (uint256 i; i < length; i++) {
      openOrders[i] = orders[_openOrders.at(cursor + i)];
    }
  }

  /**
   * @dev Returns a paginated list of open orders ids
   *
   * @param cursor Index to start at
   * @param perPage How many we want per page
   *
   * @return openOrderIds the open order Ids
   * @return nextCursor next cursor to use
   */
  function getPaginatedOpenOrderIds(uint256 cursor, uint256 perPage)
    public
    view
    returns (bytes32[] memory openOrderIds, uint256 nextCursor)
  {
    uint256 itemsCount = _openOrders.length();
    uint256 length = perPage;
    if (length > itemsCount.sub(cursor)) {
      length = itemsCount.sub(cursor);
    }

    openOrderIds = new bytes32[](length);
    for (uint256 i; i < length; i++) {
      openOrderIds[i] = _openOrders.at(cursor + i);
    }

    nextCursor = cursor + length;
  }

  /**
   * @dev returns the amount of open orders
   *
   * @return amount Number or open order
   */
  function openOrdersCount() external view returns (uint256 amount) {
    return _openOrders.length();
  }

  /**
   * @dev closes an order and remove it from the open orders
   *
   * emits OrderClosed
   */
  function _closeOrder(
    bytes32 orderId,
    OrderData memory order,
    address closer
  ) internal {
    // remove from _openOrders
    require(_openOrders.remove(orderId), 'Dex: order not open');

    emit OrderClosed(orderId, order.token, order.tokenId, closer);
  }

  /**
   * Get orderId from order data
   *
   * @return orderId from order data
   */
  function _getOrderId(OrderData memory order) internal pure returns (bytes32) {
    return keccak256(abi.encode(order));
  }

  /**
   * Verify that the current buy does not overflow the max quantity from the order
   *
   * @return a boolean declaring order completion
   */
  function _verifyOpenAndModifyState(
    bytes32 orderId,
    OrderData memory order,
    uint256 buyingAmount
  ) internal returns (bool) {
    uint256 comp = _completed[orderId].add(buyingAmount);

    // makes sure order is not already closed
    require(comp <= order.quantity, 'Dex: not enough remaining.');

    // update order completion amount
    _completed[orderId] = comp;

    // returns if order is closed or not
    return comp == order.quantity;
  }
}
