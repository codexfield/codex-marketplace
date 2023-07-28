// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

/**
 * @dev External interface of ERC1155NonTransferable declared to support ERC165 detection.
 *
 * This multi-token doesn't support token transfer or approval.
 */
interface IERC1155NonTransferable {
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);
    event URI(string value, uint256 indexed id);

    function balanceOf(address account, uint256 id) external view returns (uint256);

    function balanceOfBatch(
        address[] calldata accounts,
        uint256[] calldata ids
    ) external view returns (uint256[] memory);

    function baseURI() external view returns (string memory);

    function uri(uint256 id) external view returns (string memory);

    function mint(address to, uint256 id, uint256 value, bytes memory data) external;

    function mintBatch(address to, uint256[] memory ids, uint256[] memory values, bytes memory data) external;

    function burn(address owner, uint256 id, uint256 value) external;

    function burnBatch(address owner, uint256[] memory ids, uint256[] memory values) external;

    function setBaseURI(string calldata newURI) external;

    function setTokenURI(uint256 id, string calldata newURI) external;
}
