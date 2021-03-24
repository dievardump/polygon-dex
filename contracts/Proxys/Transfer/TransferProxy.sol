// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ITransferProxy.sol";
import "../../Access/OwnerOperatorControl.sol";

contract TransferProxy is ITransferProxy, OwnerOperatorControl {
    function initialize() public initializer {
        __OwnerOperatorControl_init();
    }

    function erc20TransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) external override onlyOperator {
        require(
            IERC20(token).transferFrom(from, to, amount),
            "TransferProxy: Error when transfering ERC20"
        );
    }

    function erc721SafeTransferFrom(
        address token,
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external override onlyOperator {
        IERC721(token).safeTransferFrom(from, to, tokenId, data);
    }

    function erc1155SafeTransferFrom(
        address token,
        address from,
        address to,
        uint256 tokenId,
        uint256 amount,
        bytes calldata data
    ) external override onlyOperator {
        IERC1155(token).safeTransferFrom(from, to, tokenId, amount, data);
    }
}