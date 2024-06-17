// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "contracts/libraries/Constants.sol";

library Util {
    function isERC721(address nft) internal view returns (bool) {
        return IERC165(nft).supportsInterface(Constants.HASH_ERC721);
    }

    function isERC1155(address nft) internal view returns (bool) {
        return IERC165(nft).supportsInterface(Constants.HASH_ERC1155);
    }

    function isETH(address token) internal pure returns (bool) {
        return token == Constants.ETH;
    }
}
