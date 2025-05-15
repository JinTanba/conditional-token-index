// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../src/ConditionalTokensIndexFactory.sol";
import "../src/ConditionalTokensIndex.sol";
import "../src/interfaces/ICTFExchange.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Compose is Script {
    address polymarket = 0xC5d563A36AE78145C45a50134d48A1215220f80a;
    address collateral =0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    IConditionalTokens ctf = IConditionalTokens(0x4D97DCd97eC945f40cF65F87097ACe5EA0476045);
    ConditionalTokensIndexFactory factory = ConditionalTokensIndexFactory(0x934ED1a863BB08d68b74939cF4D8ad644AbC1d85);
    ConditionalTokensIndex indexImpl = ConditionalTokensIndex(0x70f7f2299B254e2E53ae7D67eb85d7bBE10CaDde);
    address priceOracle = 0x9b1B5d4c95530d747bfaad5934A8E5D448a28AF5;
    // 0x3cade829b69b30436629ac0c2494d475211ba6f7e00e192a920653ba00b7db36,
    // 0x553728bcacf78928f84c20141df3927eba4e76846d67db8d354a111619501a6b,
    // 0x354b6793f25222186de8d3c9ca1e444e71a6d7b7db276bf1aa50b95b8d47cb65,
    // 0x5bf33c43674b2bc7452acca8d971ff8a84ccee5fbce29b9d4b75f8f895aa52c2
    function run() public {
        vm.startBroadcast();
        ERC20(collateral).approve(address(ctf), type(uint256).max);
        bytes32[] memory conditions = new bytes32[](4);
        conditions[0] = 0x3cade829b69b30436629ac0c2494d475211ba6f7e00e192a920653ba00b7db36;
        conditions[1] = 0x553728bcacf78928f84c20141df3927eba4e76846d67db8d354a111619501a6b;
        conditions[2] = 0x354b6793f25222186de8d3c9ca1e444e71a6d7b7db276bf1aa50b95b8d47cb65;
        conditions[3] = 0x5bf33c43674b2bc7452acca8d971ff8a84ccee5fbce29b9d4b75f8f895aa52c2;
        uint256 perUsdc = 2*10**6;
        uint256[] memory yesSlots = new uint256[](conditions.length);
        uint256[] memory noSlots = new uint256[](conditions.length);
        uint256[] memory binary = new uint256[](2);
        binary[0] = 1;
        binary[1] = 2;
        for(uint256 i=0;i<conditions.length;i++){
            bytes32 conditionId = conditions[i];
            uint256 slots = ctf.getOutcomeSlotCount(conditionId);
            require(slots>0,"InvalidCondition");
            yesSlots[i] = 1;
            noSlots[i] = 2;
            ctf.splitPosition(collateral,bytes32(0),conditionId,binary,perUsdc);
        } 

        ConditionalTokensIndexFactory.IndexImage memory yes517=ConditionalTokensIndexFactory.IndexImage({
            impl:address(indexImpl),
            conditionIds:conditions,
            indexSets:yesSlots,
            specifications:abi.encodePacked("517Up"),
            priceOracle:priceOracle
        });
        ConditionalTokensIndexFactory.IndexImage memory no517=ConditionalTokensIndexFactory.IndexImage({
            impl:address(indexImpl),
            conditionIds:conditions,
            indexSets:noSlots,
            specifications:abi.encodePacked("517Down"),
            priceOracle:priceOracle
        });
        ctf.setApprovalForAll(address(factory),true);
        ctf.setApprovalForAll(address(factory),true);
        address yes517Instance = factory.createIndex(yes517,bytes(""),perUsdc);
        address no517Instance = factory.createIndex(no517,bytes(""),perUsdc);
        console.log("yes517Instance");
        console.logAddress(yes517Instance);
        console.log("no517Instance");
        console.logAddress(no517Instance);
        vm.stopBroadcast();
    }


}
