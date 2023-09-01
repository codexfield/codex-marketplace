// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @dev External interface of ERC1155NonTransferable declared to support ERC165 detection.
 *
 * This multi-token DOESN'T support token transfer or approval.
 */
interface IERC1155NonTransferable is IERC1155 {
    function baseURI() external view returns (string memory);

    function uri(uint256 id) external view returns (string memory);

    function mint(address to, uint256 id, uint256 value, bytes memory data) external;

    function mintBatch(address to, uint256[] memory ids, uint256[] memory values, bytes memory data) external;

    function burn(address owner, uint256 id, uint256 value) external;

    function burnBatch(address owner, uint256[] memory ids, uint256[] memory values) external;

    function setBaseURI(string calldata newURI) external;

    function setTokenURI(uint256 id, string calldata newURI) external;
}
