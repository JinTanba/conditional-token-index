// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../src/ConditionalTokensIndexFactory.sol";
import "../src/ConditionalTokensIndex.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1_000_000 * 10**6); // 1M USDC with 6 decimals
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

struct IndexImage {
    address impl;
    bytes32[] conditionIds;
    uint256[] indexSets;
    bytes specifications;
}

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

contract Deploy is Test {
    function testFlow() public {
        vm.startBroadcast();
        address ctf = 0x4D97DCd97eC945f40cF65F87097ACe5EA0476045;
        address collateral = address(new MockUSDC());
        ConditionalTokensIndexFactory factory = new ConditionalTokensIndexFactory(ctf,collateral);
        ConditionalTokensIndex indexImpl = new ConditionalTokensIndex();
        address oracle = msg.sender;
        bytes32 questionId1 = keccak256("polynance test1");
        bytes32 questionId2 = keccak256("polynance test2");
        uint256 outcomeSlotCount = 2;
        uint256 amount = 2*10**6;
        address user = msg.sender;
        //1. approve
        ERC20(collateral).approve(ctf, type(uint256).max);
        ERC1155(ctf).setApprovalForAll(address(factory), true);
        //2. split
        IConditionalTokens(ctf).prepareCondition(oracle,questionId1,outcomeSlotCount);
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;

        IConditionalTokens(ctf).prepareCondition(oracle,questionId2,outcomeSlotCount);
        uint256[] memory partition2 = new uint256[](2);
        partition2[0] = 1;
        partition2[1] = 2;
        
        
        IConditionalTokens(ctf).splitPosition(collateral, bytes32(0), IConditionalTokens(ctf).getConditionId(oracle,questionId1,outcomeSlotCount), partition, amount);
        IConditionalTokens(ctf).splitPosition(collateral, bytes32(0), IConditionalTokens(ctf).getConditionId(oracle,questionId2,outcomeSlotCount), partition2, amount);
        //check balance == amount
        console.log("1. check balance");
        uint256[] memory ids = new uint256[](2);
        ids[0] = IConditionalTokens(ctf).getPositionId(collateral, IConditionalTokens(ctf).getCollectionId(bytes32(0), IConditionalTokens(ctf).getConditionId(oracle,questionId1,outcomeSlotCount), 1));
        ids[1] = IConditionalTokens(ctf).getPositionId(collateral, IConditionalTokens(ctf).getCollectionId(bytes32(0), IConditionalTokens(ctf).getConditionId(oracle,questionId2,outcomeSlotCount), 1));
        assertEq(ERC1155(ctf).balanceOf(user, ids[0]), amount);
        assertEq(ERC1155(ctf).balanceOf(user, ids[1]), amount);
        console.logUint(ids[0]);
        console.logUint(ids[1]);
        console.logUint(ERC1155(ctf).balanceOf(user, ids[0]));
        console.logUint(ERC1155(ctf).balanceOf(user, ids[1]));


       
        //3. create index
        console.log("2. create index");
        uint256[] memory indexSets = new uint256[](2);
        indexSets[0] = 1;
        indexSets[1] = 2;
        bytes32[] memory conditionIds = new bytes32[](2);
        conditionIds[0] = IConditionalTokens(ctf).getConditionId(oracle, questionId1, outcomeSlotCount);
        conditionIds[1] = IConditionalTokens(ctf).getConditionId(oracle, questionId2, outcomeSlotCount);
        
        // Create index image
        console.log("2. create index image");
        ConditionalTokensIndexFactory.IndexImage memory indexImage = ConditionalTokensIndexFactory.IndexImage({
            impl: address(indexImpl),
            conditionIds: conditionIds,
            indexSets: indexSets,
            specifications: bytes("Test Index")
        });

        ConditionalTokensIndexFactory.IndexImage memory indexImage2 = ConditionalTokensIndexFactory.IndexImage({
            impl: address(indexImpl),
            conditionIds: conditionIds,
            indexSets: indexSets,
            specifications: bytes("Test Index2")
        });
        
        // Create index with initial funding
        uint256 funding = amount;
        console.log("create index with initial funding");

        address predicted = factory.computeIndex(indexImage);
        
        ERC1155(ctf).setApprovalForAll(address(factory), true);
        address instance = factory.createIndex(indexImage, bytes(""), funding);
        console.log("instance");
        console.logAddress(instance);
        assertEq(predicted, instance,"predicted");
        uint256[] memory components =BaseConditionalTokenIndex(instance).components();
        bytes memory codeInStorageBytes = Clones.fetchCloneArgs(instance);
        bytes memory memoryInstanceSC = abi.encode(BaseConditionalTokenIndex(instance).$());
        bytes memory fromFactory = abi.encode(ConditionalTokensIndexFactory(factory).$(instance));
        console.log("codeInStorageBytes");
        console.logBytes(codeInStorageBytes);
        console.log("memoryInstanceSC");
        console.logBytes(memoryInstanceSC);
        assertEq(codeInStorageBytes, memoryInstanceSC,"codeInStorageBytes");
        assertEq(codeInStorageBytes, fromFactory,"codeInStorageBytes");
        


        assertEq(components.length, 2,"components length");
        assertEq(ERC1155(ctf).balanceOf(instance, components[0]), funding,"balance of component 0");
        assertEq(ERC1155(ctf).balanceOf(instance, components[1]), funding,"balance of component 1");
        assertEq(ERC1155(ctf).balanceOf(msg.sender, components[0]), 0,"balance of component 0");
        assertEq(ERC1155(ctf).balanceOf(msg.sender, components[1]), 0,"balance of component 1");
        assertEq(BaseConditionalTokenIndex(instance).balanceOf(msg.sender), funding,"balance of instance");
        console.log("instance");
        console.logUint(BaseConditionalTokenIndex(instance).balanceOf(msg.sender));

        //withdraw
        BaseConditionalTokenIndex(instance).withdraw(funding);
        assertEq(BaseConditionalTokenIndex(instance).balanceOf(msg.sender), 0,"balance of instance");
        assertEq(ERC1155(ctf).balanceOf(msg.sender, components[0]), funding,"balance of component 0");
        assertEq(ERC1155(ctf).balanceOf(msg.sender, components[1]), funding,"balance of component 1");

        //deposit
        uint256 depositAmount = amount / 2;
        ERC1155(ctf).setApprovalForAll(address(instance), true);
        BaseConditionalTokenIndex(instance).deposit(depositAmount);
        assertEq(BaseConditionalTokenIndex(instance).balanceOf(msg.sender), depositAmount,"balance of instance");
        assertEq(ERC1155(ctf).balanceOf(msg.sender, components[0]), funding-depositAmount,"balance of component 0");
        assertEq(ERC1155(ctf).balanceOf(msg.sender, components[1]), funding-depositAmount,"balance of component 1");
        assertEq(ERC1155(ctf).balanceOf(instance, components[0]), depositAmount,"balance of component 0");
        assertEq(ERC1155(ctf).balanceOf(instance, components[1]), depositAmount,"balance of component 1");
        //totalsupply
        assertEq(BaseConditionalTokenIndex(instance).totalSupply(), depositAmount,"total supply");
        //..deposit more
        BaseConditionalTokenIndex(instance).deposit(depositAmount);
        assertEq(BaseConditionalTokenIndex(instance).totalSupply(), depositAmount*2,"total supply");
        assertEq(ERC1155(ctf).balanceOf(instance, components[0]), depositAmount*2,"balance of component 0");
        assertEq(ERC1155(ctf).balanceOf(instance, components[1]), depositAmount*2,"balance of component 1");
        assertEq(BaseConditionalTokenIndex(instance).balanceOf(msg.sender), depositAmount*2,"balance of instance");
        
        //ctf oracle
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;
        uint256 oldBalance = ERC20(collateral).balanceOf(msg.sender);
        IConditionalTokens(ctf).reportPayouts(questionId1, payouts);
        uint256 halfAmount = BaseConditionalTokenIndex(instance).balanceOf(msg.sender)/2;
        ERC1155(ctf).setApprovalForAll(address(instance), true);
        BaseConditionalTokenIndex(instance).withdraw(halfAmount);
        uint256 redeemAmount = halfAmount;
        IConditionalTokens(ctf).redeemPositions(collateral, bytes32(0), IConditionalTokens(ctf).getConditionId(oracle,questionId1,outcomeSlotCount), indexSets);
        assertEq(ERC20(collateral).balanceOf(msg.sender), oldBalance+redeemAmount,"balance of collateral");
        assertEq(BaseConditionalTokenIndex(instance).balanceOf(msg.sender), halfAmount,"balance of instance");
        
        

        vm.stopBroadcast();
    }
}
