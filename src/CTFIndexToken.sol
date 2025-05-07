// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IConditionalTokens} from "./interfaces/IConditionalTokens.sol";
import {CTFIndexFactory} from "./CTFIndexFactory.sol";

contract CTFIndexToken is ERC20, IERC1155Receiver {
    address public immutable factory;
    uint256[] private _ids;
    bytes  private _meta;

    constructor(
        address factory_,
        uint256[] memory ids_,
        bytes memory meta_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        factory = factory_;
        _ids = ids_;
        _meta = meta_;
    }

    function getIds() external view returns (uint256[] memory) { 
        return _ids; 
    }
    function getMetadata() external view returns (bytes memory) { 
        return _meta; 
    }

    function mint(uint256 amount) external {
        IConditionalTokens c = CTFIndexFactory(factory).ctf();
        uint256 len = _ids.length;
        uint256[] memory amts = new uint256[](len);
        for (uint256 i = 0; i < len; i++) amts[i] = amount;
        c.safeBatchTransferFrom(msg.sender, address(this), _ids, amts, "");
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) external {
        IConditionalTokens c = CTFIndexFactory(factory).ctf();
        _burn(msg.sender, amount);

        uint256 len = _ids.length;
        uint256[] memory amts = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            amts[i] = amount;
        }
        c.safeBatchTransferFrom(address(this), msg.sender, _ids, amts, "");
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

    function supportsInterface(bytes4 interfaceId)
        public pure override returns (bool)
    {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
