// SPDX-License-Identifier: GPL-3.0-or-later

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

pragma solidity ^0.8.0;

/**
 * @dev External interface of ERC721NonTransferable declared to support ERC165 detection.
 *
 * This Non-Fungible Token DOESN'T support token transfer or approval.
 */
interface IERC721NonTransferable is IERC721Enumerable {
    function exists(uint256 tokenId) external view returns (bool);

    function setBaseURI(string calldata newURI) external;

    function mint(address to, uint256 tokenId) external;

    function burn(uint256 tokenId) external;
}
