// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../src/ConditionalTokensIndexFactory.sol";
import "../src/ConditionalTokensIndex.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

// MockUSDC remains unchanged
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1_000_000 * 10**6); // 1M USDC with 6 decimals
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}


contract FlowTest is Test {
    // Constants for test configuration
    address private constant CTF_REAL_ADDRESS = 0x4D97DCd97eC945f40cF65F87097ACe5EA0476045;
    string private constant QUESTION_1_TEXT = "polynance test1";
    string private constant QUESTION_2_TEXT = "polynance test2";
    uint256 private constant DEFAULT_OUTCOME_SLOT_COUNT = 2;
    uint256 private constant MINT_AMOUNT = 2 * 10**6; // Default amount for splits/funding

    // State variables initialized in setUp and used across tests
    IConditionalTokens internal ctfInterface;
    MockUSDC internal collateralToken;
    ConditionalTokensIndexFactory internal factory;
    ConditionalTokensIndex internal indexImplementation; // Base implementation for proxies

    address internal oracleAddress;
    address internal userAddress;
    address internal priceOracle;
    bytes32 internal questionId1;
    bytes32 internal questionId2;
    bytes32 internal conditionId1;
    bytes32 internal conditionId2;

    uint256[] internal defaultPartitionForSplit;
    uint256[] internal defaultIndexSetsForImage;


    function setUp() public virtual {
        // Start broadcast for setup transactions that change state
        vm.startBroadcast();

        collateralToken = new MockUSDC();
        ctfInterface = IConditionalTokens(CTF_REAL_ADDRESS);
        factory = new ConditionalTokensIndexFactory(address(ctfInterface), address(collateralToken));
        indexImplementation = new ConditionalTokensIndex();
        priceOracle = address(indexImplementation);

        oracleAddress = msg.sender;
        userAddress = msg.sender;

        // Base approvals
        collateralToken.approve(address(ctfInterface), type(uint256).max);
        ERC1155(address(ctfInterface)).setApprovalForAll(address(factory), true);

        // Prepare conditions
        questionId1 = keccak256(abi.encodePacked(QUESTION_1_TEXT));
        questionId2 = keccak256(abi.encodePacked(QUESTION_2_TEXT));

        ctfInterface.prepareCondition(oracleAddress, questionId1, DEFAULT_OUTCOME_SLOT_COUNT);
        ctfInterface.prepareCondition(oracleAddress, questionId2, DEFAULT_OUTCOME_SLOT_COUNT);

        conditionId1 = ctfInterface.getConditionId(oracleAddress, questionId1, DEFAULT_OUTCOME_SLOT_COUNT);
        conditionId2 = ctfInterface.getConditionId(oracleAddress, questionId2, DEFAULT_OUTCOME_SLOT_COUNT);

        // Define default partition and index sets (as used in original test)
        defaultPartitionForSplit = new uint256[](2);
        defaultPartitionForSplit[0] = 1;
        defaultPartitionForSplit[1] = 2;

        defaultIndexSetsForImage = new uint256[](2);
        defaultIndexSetsForImage[0] = 1; // Corresponds to outcome 0 (e.g., 1 << 0)
        defaultIndexSetsForImage[1] = 2; // Corresponds to outcome 1 (e.g., 1 << 1)

        vm.stopBroadcast();
    }

    function test_SplitPositionsAndVerifyBalances() public {
        vm.startBroadcast();
        console.log("Test: Splitting positions and verifying balances...");

        ctfInterface.splitPosition(address(collateralToken), bytes32(0), conditionId1, defaultPartitionForSplit, MINT_AMOUNT);
        ctfInterface.splitPosition(address(collateralToken), bytes32(0), conditionId2, defaultPartitionForSplit, MINT_AMOUNT);

        console.log("Verifying balances after splitting positions...");
        bytes32 collectionId1_Outcome0 = ctfInterface.getCollectionId(bytes32(0), conditionId1, defaultIndexSetsForImage[0]); // Using indexSet 1 (outcome 0)
        uint256 positionId1_Outcome0 = ctfInterface.getPositionId(address(collateralToken), collectionId1_Outcome0);

        bytes32 collectionId2_Outcome0 = ctfInterface.getCollectionId(bytes32(0), conditionId2, defaultIndexSetsForImage[0]); // Using indexSet 1 (outcome 0)
        uint256 positionId2_Outcome0 = ctfInterface.getPositionId(address(collateralToken), collectionId2_Outcome0);

        assertEq(ERC1155(address(ctfInterface)).balanceOf(userAddress, positionId1_Outcome0), MINT_AMOUNT, "User balance of position for (Condition1, Outcome0) incorrect");
        assertEq(ERC1155(address(ctfInterface)).balanceOf(userAddress, positionId2_Outcome0), MINT_AMOUNT, "User balance of position for (Condition2, Outcome0) incorrect");

        console.log("Position ID for Condition 1, Outcome 0 (IndexSet 1): %s", positionId1_Outcome0);
        console.log("User balance for Position ID (Cond1, Outcome0): %s", ERC1155(address(ctfInterface)).balanceOf(userAddress, positionId1_Outcome0));
        vm.stopBroadcast();
    }

    function test_CreateIndexAndInitialFunding() public {
        vm.startBroadcast();
        console.log("Test: Creating index and verifying initial funding...");

        // Ensure positions are split for the index components (as they are prerequisites for funding)
        ctfInterface.splitPosition(address(collateralToken), bytes32(0), conditionId1, defaultPartitionForSplit, MINT_AMOUNT);
        ctfInterface.splitPosition(address(collateralToken), bytes32(0), conditionId2, defaultPartitionForSplit, MINT_AMOUNT);
        // Factory approval is in setUp, but good to remember it's needed. ERC1155(address(ctfInterface)).setApprovalForAll(address(factory), true);


        bytes32[] memory conditionIdsForImage = new bytes32[](2);
        conditionIdsForImage[0] = conditionId1;
        conditionIdsForImage[1] = conditionId2;
        
        ConditionalTokensIndexFactory.IndexImage memory indexImage = ConditionalTokensIndexFactory.IndexImage({
            impl: address(indexImplementation),
            conditionIds: conditionIdsForImage,
            indexSets: defaultIndexSetsForImage,
            specifications: bytes("Test Index Create"),
            priceOracle: priceOracle
        });
        
        uint256 initialFundingAmount = MINT_AMOUNT;
        address predictedIndexAddress = factory.computeIndex(indexImage);
        address indexInstanceAddress = factory.createIndex(indexImage, bytes(""), initialFundingAmount);
        
        console.log("Created Index Instance Address: %s", indexInstanceAddress);
        assertEq(predictedIndexAddress, indexInstanceAddress, "Predicted index address should match actual");

        // Low-level Proxy Storage/Code Checks
        uint256[] memory components = BaseConditionalTokenIndex(indexInstanceAddress).components();
        console.log(BaseConditionalTokenIndex(indexInstanceAddress).name());
        console.log(BaseConditionalTokenIndex(indexInstanceAddress).symbol());
        bytes memory codeInStorageBytes = Clones.fetchCloneArgs(indexInstanceAddress);
        // Assuming BaseConditionalTokenIndex and ConditionalTokensIndexFactory have a '$()' function
        // If not, these lines would need adjustment to the actual methods for fetching storage representations.
        bytes memory memoryInstanceSC = abi.encode(BaseConditionalTokenIndex(indexInstanceAddress).$());
        bytes memory fromFactory = abi.encode(ConditionalTokensIndexFactory(factory).$(indexInstanceAddress));
        
        assertEq(codeInStorageBytes, memoryInstanceSC, "Mismatch: Cloned args vs Index internal storage representation");
        assertEq(codeInStorageBytes, fromFactory, "Mismatch: Cloned args vs Factory internal storage representation");
        
        // Assertions for Index State After Creation
        assertEq(components.length, 2, "Components array length should be 2");
        assertEq(ERC1155(address(ctfInterface)).balanceOf(indexInstanceAddress, components[0]), initialFundingAmount, "Index balance of component 0 incorrect post-creation");
        assertEq(ERC1155(address(ctfInterface)).balanceOf(indexInstanceAddress, components[1]), initialFundingAmount, "Index balance of component 1 incorrect post-creation");
        assertEq(BaseConditionalTokenIndex(indexInstanceAddress).balanceOf(userAddress), initialFundingAmount, "User's index token balance incorrect post-creation");
        vm.stopBroadcast();
    }

    function test_IndexDepositAndWithdraw() public {
        console.log("Test: Index deposit and withdraw operations...");
        // Step 1: Create and fund an index for this test scope
        vm.startBroadcast();
        ctfInterface.splitPosition(address(collateralToken), bytes32(0), conditionId1, defaultPartitionForSplit, MINT_AMOUNT);
        ctfInterface.splitPosition(address(collateralToken), bytes32(0), conditionId2, defaultPartitionForSplit, MINT_AMOUNT);
        
        bytes32[] memory cIds = new bytes32[](2); cIds[0] = conditionId1; cIds[1] = conditionId2;
        ConditionalTokensIndexFactory.IndexImage memory img = ConditionalTokensIndexFactory.IndexImage(address(indexImplementation), cIds, defaultIndexSetsForImage, bytes("Test Deposit/Withdraw"), priceOracle);
        uint256 funding = MINT_AMOUNT;
        address testIndex = factory.createIndex(img, bytes(""), funding);
        uint256[] memory components = BaseConditionalTokenIndex(testIndex).components();
        vm.stopBroadcast();

        // Step 2: Test Withdraw
        vm.startBroadcast();
        console.log("Withdrawing from index...");
        BaseConditionalTokenIndex(testIndex).withdraw(funding);
        assertEq(BaseConditionalTokenIndex(testIndex).balanceOf(userAddress), 0, "User index tokens after full withdraw");
        assertEq(ERC1155(address(ctfInterface)).balanceOf(userAddress, components[0]), funding, "User component 0 balance after withdraw");
        assertEq(ERC1155(address(ctfInterface)).balanceOf(userAddress, components[1]), funding, "User component 1 balance after withdraw");
        vm.stopBroadcast();

        // Step 3: Test Deposit
        vm.startBroadcast();
        console.log("Depositing to index...");
        uint256 depositAmount = MINT_AMOUNT / 2;
        ERC1155(address(ctfInterface)).setApprovalForAll(testIndex, true); // Approve index to take components from user
        BaseConditionalTokenIndex(testIndex).deposit(depositAmount);

        assertEq(BaseConditionalTokenIndex(testIndex).balanceOf(userAddress), depositAmount, "User index tokens after 1st deposit");
        assertEq(ERC1155(address(ctfInterface)).balanceOf(testIndex, components[0]), depositAmount, "Index component 0 balance after 1st deposit");
        assertEq(BaseConditionalTokenIndex(testIndex).totalSupply(), depositAmount, "Total supply after 1st deposit");

        // Deposit more
        BaseConditionalTokenIndex(testIndex).deposit(depositAmount);
        assertEq(BaseConditionalTokenIndex(testIndex).balanceOf(userAddress), MINT_AMOUNT, "User index tokens after 2nd deposit");
        assertEq(BaseConditionalTokenIndex(testIndex).totalSupply(), MINT_AMOUNT, "Total supply after 2nd deposit");
        assertEq(ERC1155(address(ctfInterface)).balanceOf(testIndex, components[0]), MINT_AMOUNT, "Index component 0 balance after 2nd deposit");
        vm.stopBroadcast();
    }

}