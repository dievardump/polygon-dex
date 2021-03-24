// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;

interface ITransferProxy {
    function erc20TransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) external;

    function erc721SafeTransferFrom(
        address token,
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;

    function erc1155SafeTransferFrom(
        address token,
        address from,
        address to,
        uint256 tokenId,
        uint256 amount,
        bytes calldata data
    ) external;
}
