// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {IConditionalTokens} from "./interfaces/IConditionalTokens.sol";
import {CTFIndexToken} from "./CTFIndexToken.sol";

// @dev
// Invariant conditions:
// 1. If the set of positionids is the same, and the metadata and ctf addresses are the same, calculate the same indextoken.
// 2. An indextoken is issued and can be withdrawn in a 1:1 ratio with the position token it contains.
// 3. An indextoken cannot have two or more positions under the same conditionid.

contract CTFIndexFactory {

    event IndexCreated(
        address indexed index,
        bytes32 indexed salt,
        uint256[] indexSets,
        bytes metadata
    );


    IConditionalTokens public immutable ctf;
    address public immutable collateral;
    mapping(bytes32 => address) public getIndex;

    error LengthMismatch();
    error InvalidOrder();
    error InvalidIndexSet();
    error IndexAlreadyExists();
    error InvalidCondition();
    error DuplicateCondition();

    constructor(address _ctf, address _collateral) {
        ctf = IConditionalTokens(_ctf);
        collateral = _collateral;
    }

    function bundlePosition(
        bytes32[] calldata conditionIds,
        uint256[] calldata indexSets,
        bytes calldata metadata
    ) external returns (address index) {

        (
            bytes32 salt, 
            bytes memory initCode
        ) = _preparePosition(conditionIds, indexSets, metadata);

        _validatePosition(conditionIds, indexSets);


        address predicted = address(
            uint160(uint256(
            keccak256(
                abi.encodePacked(
                    bytes1(0xff), address(this), salt, keccak256(initCode)
                )
            )
        )));

        if(predicted.code.length != 0) return predicted;

        //CREATE2 deploy
        assembly {
            let ptr := add(initCode, 0x20)
            let len := mload(initCode)
            index := create2(0, ptr, len, salt)
            if iszero(index) { revert(0, 0) }
        }

        CTFIndexToken(index).initialize(
            indexSets, 
            conditionIds, 
            metadata,
            collateral,
            address(ctf)
        );

        getIndex[salt] = index;
        emit IndexCreated(index, salt, indexSets, metadata);
    }

    function calculateIndexAddress(
        bytes32[] calldata conditionIds,
        uint256[] calldata indexSets,
        bytes calldata metadata
    ) external view returns (address predicted) {

        (bytes32 salt, bytes memory initCode) = _preparePosition(conditionIds, indexSets, metadata);

        predicted = address(
            uint160(uint256(
            keccak256(
                abi.encodePacked(
                    bytes1(0xff), address(this), salt, keccak256(initCode)
                )
            )
        )));
    }

    function _preparePosition(
        bytes32[] calldata conditionIds,
        uint256[] calldata indexSets,
        bytes calldata metadata
    )
        internal
        pure
        returns (
            bytes32 salt,
            bytes memory initCode
        )
    {
            unchecked {
                for (uint256 i; i < conditionIds.length; ++i) {
                    salt ^= keccak256(abi.encodePacked(conditionIds[i], indexSets[i]));
                }
                salt ^= bytes32(conditionIds.length);       // mix in cardinality
                salt ^= keccak256(metadata); 
            }

            string memory suffix = Strings.toHexString(uint256(salt));
            string memory name = string(abi.encodePacked("CTFIndex-", suffix));
            string memory symbol = string(abi.encodePacked("CTFI.",suffix));
            initCode = abi.encodePacked(
                type(CTFIndexToken).creationCode,
                abi.encode(name, symbol)            // constructor args
            );
    }

    function _validatePosition(
        bytes32[] calldata conditionIds,
        uint256[] calldata indexSets
    ) internal view {
        for(uint256 i; i < conditionIds.length; ++i) {
            uint256 slots = ctf.getOutcomeSlotCount(conditionIds[i]);
            if(slots == 0) revert InvalidCondition();
            if (indexSets[i] == 0 || indexSets[i] >= (1 << slots)) revert InvalidIndexSet();
            for(uint256 j; j < conditionIds.length; ++j) {
                if(i == j) continue;
                if(conditionIds[i] == conditionIds[j]) revert DuplicateCondition();
            }
        }
    }

}
