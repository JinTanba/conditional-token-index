// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import {IConditionalTokens} from "./interfaces/IConditionalTokens.sol";
// @dev
// Invariant conditions:
// 1. If the set of positionids is the same, and the metadata and ctf addresses are the same, calculate the same indextoken.
// 2. An indextoken is issued and can be withdrawn in a 1:1 ratio with the position token it contains.
// 3. An indextoken cannot have two or more positions under the same conditionid.
abstract contract BaseConditionalTokenIndex is ERC20, IERC1155Receiver, ERC165 {

    struct StorageInCode{
        uint256[] components;
        bytes32[] conditionIds;
        uint256[] indexSets;
        bytes specifications;
        address factory;
        address ctf;
        address collateral;
        address impl;
    }

    constructor() ERC20("",""){}

    function initialize(bytes calldata initData) external virtual {
        require(msg.sender == $().factory,"PermissonError");
        _init(initData);
    }

    function deposit(uint256 amount) external {
        uint256 len = components().length;
        uint256[] memory amts = new uint256[](len);
        unchecked {
            for (uint256 i = 0; i < len; ++i) {
                amts[i] = amount;
            }
        }
        _mint(msg.sender, amount);
        ctf().safeBatchTransferFrom(msg.sender, address(this), components(), amts, "");
    }

    function withdraw(uint256 amount) external {
        uint256 len = components().length;

        uint256[] memory amts = new uint256[](len);
        unchecked {
            for (uint256 i = 0; i < len; ++i) {
                amts[i] = amount;
            }
        }
        _burn(msg.sender, amount);
        ctf().safeBatchTransferFrom(address(this), msg.sender, components(), amts, "");
    }

    function $() public view returns (StorageInCode memory args) {
        args = abi.decode(Clones.fetchCloneArgs(address(this)), (StorageInCode));
    }

    function immutableArgsRaw() external view returns (bytes memory) {
        return Clones.fetchCloneArgs(address(this));
    }

    /// @notice Component array getter
    function components() public view returns (uint256[] memory) {
        return $().components;
    }

    /// @notice Condition IDs getter
    function conditionIds() public view returns (bytes32[] memory) {
        return $().conditionIds;
    }

    /// @notice Index sets getter
    function indexSets() public view returns (uint256[] memory) {
        return $().indexSets;
    }

    function encodedSpecifications() public view returns (bytes memory) {
        return $().specifications;
    }

    function ctf() public view returns (IConditionalTokens) {
        return IConditionalTokens($().ctf);
    }

    function collateral() public view returns(address) {
        return $().collateral;
    }

    function _init(bytes memory initData) internal virtual {}

    function name() public override view returns (string memory) {
        bytes32 h = keccak256(Clones.fetchCloneArgs(address(this)));
        return string(abi.encodePacked("CTI-", _toHexString(h)));
    }

    function symbol() public override view returns (string memory) {
        bytes32 h = keccak256(Clones.fetchCloneArgs(address(this)));
        return string(abi.encodePacked("X-", _toHexString(h)));
    }

    /// @dev EIP-1155 receiver hooks
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

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC165, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @dev Convert bytes32 to 0x-prefixed hex string
    function _toHexString(bytes32 data) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory str = new bytes(2 + 64);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 32; i++) {
            str[2 + i * 2] = hexChars[uint8(data[i] >> 4)];
            str[3 + i * 2] = hexChars[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }
}


