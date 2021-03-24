//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';

contract ERC721Dummy is ERC721 {
  constructor() ERC721('Test', 'TEST') {
    _setBaseURI('fakeAPI/');
    _mint(_msgSender(), 1);
    _mint(_msgSender(), 2);
    _mint(_msgSender(), 3);
  }

  function mint(uint256 id) external {
    _mint(_msgSender(), id);
  }
}
