// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IConditionalTokens} from "./interfaces/IConditionalTokens.sol";
import {CTFIndexFactory} from "./CTFIndexFactory.sol";
// @dev
// Invariant conditions:
// 1. If the set of positionids is the same, and the metadata and ctf addresses are the same, calculate the same indextoken.
// 2. An indextoken is issued and can be withdrawn in a 1:1 ratio with the position token it contains.
// 3. An indextoken cannot have two or more positions under the same conditionid.

contract CTFIndexToken is ERC20, IERC1155Receiver {
    address public immutable factory;
    uint256[] internal _indexSets;
    bytes32[] internal _conditionIds;
    uint256 internal _createdAt;
    bytes internal _metadata;
    address internal collateral;
    IConditionalTokens internal ctf;

    error OnlyFactory();
    error AlreadyInitialised();
    error LengthMismatch();

    modifier onlyFactory() {
        if (msg.sender != factory) revert OnlyFactory();
        _;
    }

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        factory = msg.sender;
    }

    /**
     * @notice Store sorted `(conditionId, indexSet)` arrays after deployment.
     * @dev    Factory sorts and validates; token only records.
     */
    function initialize(
        uint256[] calldata indexSets,
        bytes32[] calldata conditionIds,
        bytes calldata metadata_,
        address collateral_,
        address ctf_
    ) external onlyFactory {
        if (_createdAt != 0) revert AlreadyInitialised();
        uint256 n = indexSets.length;
        if (n == 0 || n != conditionIds.length) revert LengthMismatch();

        _indexSets = indexSets;
        _conditionIds = conditionIds;
        _metadata = metadata_;
        _createdAt = block.timestamp;
        collateral = collateral_;
        ctf = IConditionalTokens(ctf_);
    }

    function mint(uint256 amount) external {
        uint256 len = _indexSets.length;

        uint256[] memory ids = new uint256[](len);
        uint256[] memory amts = new uint256[](len);
        unchecked {
            for (uint256 i = 0; i < len; ++i) {
                ids[i] = _positionId(_conditionIds[i], _indexSets[i]);
                amts[i] = amount;
            }
        }

        ctf.safeBatchTransferFrom(msg.sender, address(this), ids, amts, "");
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        uint256 len = _indexSets.length;

        uint256[] memory ids = new uint256[](len);
        uint256[] memory amts = new uint256[](len);
        unchecked {
            for (uint256 i = 0; i < len; ++i) {
                ids[i] = _positionId(_conditionIds[i], _indexSets[i]);
                amts[i] = amount;
            }
        }
        ctf.safeBatchTransferFrom(address(this), msg.sender, ids, amts, "");
    }

    function burnAndRedeem(uint256 amount) external {
        _burn(msg.sender, amount);
        uint256 len = _indexSets.length;
        uint256 beforeCollateralBalance = IERC20(collateral).balanceOf(address(this));
        unchecked {
            for (uint256 i = 0; i < len; ++i) {
                uint256[] memory ids = new uint256[](1);
                ids[0] = _indexSets[i];
                ctf.redeemPositions(collateral, bytes32(0), _conditionIds[i], ids);
            }
        }
        uint256 redeemedCollateral = IERC20(collateral).balanceOf(address(this)) - beforeCollateralBalance;
        IERC20(collateral).transfer(msg.sender, redeemedCollateral);
    }

    function getIndexSets() external view returns (uint256[] memory) {
        return _indexSets;
    }
    function getConditionIds() external view returns (bytes32[] memory) {
        return _conditionIds;
    }
    function metadata() external view returns (bytes memory) {
        return _metadata;
    }
    function createdAt() external view returns (uint256) {
        return _createdAt;
    }

    function _positionId(bytes32 conditionId, uint256 indexSet) internal view returns (uint256) {
        return ctf.getPositionId(collateral, ctf.getCollectionId(bytes32(0), conditionId, indexSet));
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
