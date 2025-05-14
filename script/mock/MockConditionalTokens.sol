// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/**
 * @dev Ultra-thin ERC-1155 stub that is “just good enough” for the factory &
 *      index flows.  Five functions, no oracle logic, no disputes.
 */
contract MockConditionalTokens is ERC1155, ERC1155Holder {
    mapping(bytes32 => uint256) private _slotCount;

    constructor() ERC1155("") {}

    /* ---------- Test helpers ---------- */

    function setOutcomeSlotCount(bytes32 conditionId, uint256 slots) external {
        _slotCount[conditionId] = slots;
    }

    function mint(
        address to,
        uint256 id,
        uint256 amount
    ) external {
        _mint(to, id, amount, "");
    }

    /* ---------- IConditionalTokens ---------- */

    function getOutcomeSlotCount(bytes32 conditionId)
        external
        view
        returns (uint256)
    {
        return _slotCount[conditionId];
    }

    function getCollectionId(
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256 indexSet
    ) external pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(parentCollectionId, conditionId, indexSet)
            );
    }

    function getPositionId(
        address collateralToken,
        bytes32 collectionId
    ) external pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(collateralToken, collectionId)));
    }
    
    // Override supportsInterface to resolve conflict between ERC1155 and ERC1155Holder
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, ERC1155Holder) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
