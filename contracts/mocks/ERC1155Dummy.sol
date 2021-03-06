//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';

contract ERC1155Dummy is ERC1155 {
  constructor() ERC1155('fakeAPI/') {
    _mint(_msgSender(), 1, 10, bytes(''));
    _mint(_msgSender(), 2, 10, bytes(''));
    _mint(_msgSender(), 3, 10, bytes(''));
  }

  function mint(uint256 id) external {
    _mint(_msgSender(), id, 10, bytes(''));
  }
}
