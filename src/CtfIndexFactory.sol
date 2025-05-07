// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {IConditionalTokens} from "./interfaces/IConditionalTokens.sol";
import {CTFIndexToken} from "./CTFIndexToken.sol";



contract CTFIndexFactory {
    using Strings for uint256;

    IConditionalTokens public immutable ctf;
    address public immutable collateral;
    mapping(bytes32 => address) public getIndex;

    constructor(address _ctf, address _collateral) {
        ctf = IConditionalTokens(_ctf);
        collateral = _collateral;
    }

    /**
     * @dev Validates that ids and conditionIds have matching length,
     *      that ids are strictly ascending (unique), and that each
     *      id matches its corresponding condition. Returns ids as-is.
     */
    function prepareIndex(
        uint256[] calldata ids,
        bytes32[] calldata conditionIds,
        bytes calldata metadata
    ) internal view returns (
        uint256[] memory filtered,
        bytes32 salt,
        string memory name,
        string memory symbol
    ) {

        uint256 len = ids.length;
        require(len > 0, "no ids");
        require(len < 256, "too many ids");
        require(conditionIds.length == len, "array mismatch");

        for (uint256 i = 1; i < len; i++) {
            require(ids[i] > ids[i - 1], "ids not sorted or duplicate");
        }

        for (uint256 i = 0; i < len; i++) {
            bytes32 cond = conditionIds[i];
            uint256 outcomeCount = ctf.getOutcomeSlotCount(cond);
            bool matchFound;
            for (uint256 idx = 0; idx < outcomeCount; idx++) {
                if (ctf.getPositionId(collateral, ctf.getCollectionId(bytes32(0), cond, idx)) == ids[i]) {
                    matchFound = true;
                    break;
                }
            }
            require(matchFound, "id vs condition mismatch");
        }

        filtered = ids;
        bytes32 idsHash = keccak256(abi.encodePacked(filtered));
        salt = keccak256(abi.encodePacked(ctf, metadata, len, idsHash));

        string memory suffix = Strings.toHexString(uint256(salt));
        name = string(abi.encodePacked("CTFIndex-", suffix));
        symbol = string(abi.encodePacked("CTFI.", suffix));
    }

    function createIndex(
        uint256[] calldata ids,
        bytes32[] calldata conditionIds,
        bytes calldata metadata
    ) external returns (address index) {

        (
            uint256[] memory filtered, 
            bytes32 salt, 
            string memory name, 
            string memory symbol
        ) = prepareIndex(ids, conditionIds, metadata);

        require(getIndex[salt] == address(0), "exists");
    
        bytes memory initCode = abi.encodePacked(
            type(CTFIndexToken).creationCode,
            abi.encode(address(this), filtered, metadata, name, symbol)
        );

        assembly {
            index := create2(0, add(initCode, 0x20), mload(initCode), salt)
            if iszero(index) { revert(0, 0) }
        }

        getIndex[salt] = index;
        emit IndexCreated(index, salt, filtered, metadata);
    }

    function predictIndexAddress(
        uint256[] calldata ids,
        bytes32[] calldata conditionIds,
        bytes calldata metadata
    ) external view returns (address) {
        (
            uint256[] memory filtered, 
            bytes32 salt,
            string memory name, 
            string memory symbol
        ) = prepareIndex(ids, conditionIds, metadata);

        bytes memory initCode = abi.encodePacked(
            type(CTFIndexToken).creationCode,
            abi.encode(address(this), filtered, metadata, name, symbol)
        );
        bytes32 codeHash = keccak256(initCode);
        return address(uint160(uint256(
            keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, codeHash)))
        ));
    }

    event IndexCreated(
        address indexed index,
        bytes32 indexed salt,
        uint256[] ids,
        bytes metadata
    );
}
