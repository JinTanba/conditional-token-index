// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Interface for ConditionalTokens
interface IConditionalTokens {
    function prepareCondition(address oracle, bytes32 questionId, uint256 outcomeSlotCount) external;
    function reportPayouts(bytes32 questionId, uint256[] calldata payouts) external;
    function splitPosition(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;
    function redeemPositions(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external;
    function getPositionId(address collateralToken, bytes32 collectionId) external view returns (uint256);
    function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint256 indexSet) external view returns (bytes32);
    function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount) external pure returns (bytes32);
    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint256);
    function payoutDenominator(bytes32 conditionId) external view returns (uint256);
    function payoutNumerators(bytes32 conditionId, uint256 index) external view returns (uint256);
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function setApprovalForAll(address operator, bool approved) external;
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;
}

// Mock ERC20 token for testing
contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string public name = "Mock USDC";
    string public symbol = "mUSDC";
    uint8 public decimals = 6;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function totalSupply() external view returns (uint256) { return _totalSupply; }
    function balanceOf(address account) external view returns (uint256) { return _balances[account]; }
    function transfer(address to, uint256 amount) external returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }
    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

// Import the contracts we want to test
import {ConditionalTokensIndexFactory} from "../src/ConditionalTokensIndexFactory.sol";
import {BaseConditionalTokenIndex} from "../src/BaseConditionalTokenIndex.sol";

// Simple implementation for testing
contract SimpleConditionalTokenIndex is BaseConditionalTokenIndex {
    constructor() BaseConditionalTokenIndex() {}
}

contract CTFIndexRedeemTest is Test {
    // Fork configuration
    string internal constant POLYGON_RPC_URL = "https://polygon-mainnet.g.alchemy.com/v2/cidppsnxqV4JafKXVW7qd9N2x6wTvTpN";
    uint256 internal constant FORK_BLOCK_NUMBER = 72384249;
    
    // CTF address on Polygon
    IConditionalTokens internal constant CTF = IConditionalTokens(0x4D97DCd97eC945f40cF65F87097ACe5EA0476045);
    
    // Test contracts
    ConditionalTokensIndexFactory internal factory;
    SimpleConditionalTokenIndex internal indexImpl;
    MockERC20 internal collateralToken;
    
    // Test addresses
    address internal oracle = address(0x1234);
    address internal user = address(0x5678);
    address internal deployer = address(this);
    
    // Test data
    bytes32 internal questionId1 = keccak256("Will ETH reach $5000 by end of 2024?");
    bytes32 internal questionId2 = keccak256("Will BTC reach $100000 by end of 2024?");
    bytes32 internal conditionId1;
    bytes32 internal conditionId2;
    
    uint256 internal constant OUTCOME_SLOTS = 2; // YES/NO
    uint256 internal constant INITIAL_FUNDING = 1000 * 1e6; // 1000 tokens
    
    function setUp() public {
        // Fork Polygon
        vm.createFork(POLYGON_RPC_URL, FORK_BLOCK_NUMBER);
        vm.selectFork(0);
        
        // Deploy mock collateral token
        collateralToken = new MockERC20();
        
        // Deploy index implementation
        indexImpl = new SimpleConditionalTokenIndex();
        
        // Deploy factory
        factory = new ConditionalTokensIndexFactory(address(CTF), address(collateralToken));
        
        // Mint tokens to user and deployer
        collateralToken.mint(user, INITIAL_FUNDING * 10);
        collateralToken.mint(deployer, INITIAL_FUNDING * 10);
        
        // Create conditions on CTF
        conditionId1 = CTF.getConditionId(oracle, questionId1, OUTCOME_SLOTS);
        conditionId2 = CTF.getConditionId(oracle, questionId2, OUTCOME_SLOTS);
        
        CTF.prepareCondition(oracle, questionId1, OUTCOME_SLOTS);
        CTF.prepareCondition(oracle, questionId2, OUTCOME_SLOTS);
        
        console.log("Condition 1 ID:", vm.toString(conditionId1));
        console.log("Condition 2 ID:", vm.toString(conditionId2));
    }
    
    function test_CreateAndRedeemIndex() public {
        console.log("=== Starting CTF Index Redeem Test ===");
        
        // 1. Create conditional tokens by splitting collateral (EOA: user)
        _createConditionalTokens();
        
        // 2. Create index (EOA: user)
        address indexAddress = _createIndex();
        BaseConditionalTokenIndex index = BaseConditionalTokenIndex(indexAddress);
        
        console.log("Index created at:", indexAddress);
        console.log("Index name:", index.name());
        console.log("Index symbol:", index.symbol());
        
        // 3. Fund the index (EOA: user)
        _fundIndex(index);
        
        // 4. Verify index state before resolution
        assertFalse(index.indexSolved(), "Index should not be solved yet");
        assertFalse(index.canSolveIndex(), "Should not be able to solve - conditions not resolved");
        
        uint256 userBalance = index.balanceOf(user);
        console.log("User index token balance:", userBalance);
        assertEq(userBalance, INITIAL_FUNDING, "User should have index tokens");
        
        // 5. Simulate redeem before resolution (should return 0)
        (uint256 expectedPayout, bool allResolved) = index.simulateRedeem(userBalance);
        assertFalse(allResolved, "Conditions should not be resolved yet");
        assertEq(expectedPayout, 0, "Expected payout should be 0 before resolution");
        
        // 6. Resolve conditions (EOA: oracle)
        _resolveConditions();
        
        // 7. Verify index can now be solved
        assertTrue(index.canSolveIndex(), "Should be able to solve now");
        
        // 8. Simulate redeem after resolution
        (expectedPayout, allResolved) = index.simulateRedeem(userBalance);
        assertTrue(allResolved, "All conditions should be resolved");
        console.log("Expected payout after resolution:", expectedPayout);
        
        // 9. Solve the index (EOA: user)
        console.log("9. User solving the index...");
        vm.startPrank(user);
        index.solveIndex();
        vm.stopPrank();
        assertTrue(index.indexSolved(), "Index should be solved");
        
        uint256 totalRedeemed = index.totalCollateralRedeemed();
        uint256 redemptionPool = index.getRedemptionPoolBalance();
        console.log("Total collateral redeemed:", totalRedeemed);
        console.log("Redemption pool balance:", redemptionPool);
        
        // 10. Test redeem functionality (EOA: user)
        console.log("10. User redeeming index tokens...");
        vm.startPrank(user);
        
        uint256 userCollateralBefore = collateralToken.balanceOf(user);
        uint256 claimableAmount = index.getClaimableCollateral(userBalance);
        console.log("Claimable collateral for user:", claimableAmount);
        
        // Redeem tokens
        index.redeem();
        
        uint256 userCollateralAfter = collateralToken.balanceOf(user);
        uint256 userIndexBalanceAfter = index.balanceOf(user);
        
        console.log("User collateral before redeem:", userCollateralBefore);
        console.log("User collateral after redeem:", userCollateralAfter);
        console.log("User index balance after redeem:", userIndexBalanceAfter);
        
        // Verify redemption worked correctly
        assertEq(userIndexBalanceAfter, 0, "User should have no index tokens after redeem");
        assertGt(userCollateralAfter, userCollateralBefore, "User should have received collateral");
        assertEq(userCollateralAfter - userCollateralBefore, claimableAmount, "User should receive exactly the claimable amount");
        
        vm.stopPrank();
        
        // 11. Verify contract state after redemption
        uint256 claimedCollateral = index.getClaimedCollateral();
        console.log("Total claimed collateral:", claimedCollateral);
        
        console.log("=== Test completed successfully ===");
    }
    
    function _createConditionalTokens() internal {
        console.log("5. Creating conditional tokens...");
        
        // Split positions for both conditions (creating YES/NO tokens)
        uint256[] memory partition1 = new uint256[](2);
        partition1[0] = 1; // YES outcome (index set = 1)
        partition1[1] = 2; // NO outcome (index set = 2)
        
        uint256[] memory partition2 = new uint256[](2);
        partition2[0] = 1; // YES outcome
        partition2[1] = 2; // NO outcome
        
        // Only user (EOA) creates conditional tokens
        vm.startPrank(user);
        collateralToken.approve(address(CTF), type(uint256).max);
        
        CTF.splitPosition(
            address(collateralToken),
            bytes32(0),
            conditionId1,
            partition1,
            INITIAL_FUNDING * 2 // Create enough for index funding
        );
        
        CTF.splitPosition(
            address(collateralToken),
            bytes32(0),
            conditionId2,
            partition2,
            INITIAL_FUNDING * 2 // Create enough for index funding
        );
        vm.stopPrank();
        
        console.log("User created conditional tokens");
    }
    
    function _createIndex() internal returns (address) {
        console.log("6. Creating index...");
        
        // Create index for YES outcomes on both conditions
        bytes32[] memory conditionIds = new bytes32[](2);
        conditionIds[0] = conditionId1;
        conditionIds[1] = conditionId2;
        
        uint256[] memory indexSets = new uint256[](2);
        indexSets[0] = 1; // YES for condition 1
        indexSets[1] = 1; // YES for condition 2
        
        ConditionalTokensIndexFactory.IndexImage memory indexImage = ConditionalTokensIndexFactory.IndexImage({
            impl: address(indexImpl),
            conditionIds: conditionIds,
            indexSets: indexSets,
            specifications: abi.encode("ETH & BTC Bull Index", "Combination index betting on both ETH $5k and BTC $100k"),
            priceOracle: address(999999)
        });
        
        bytes memory initData = abi.encode("ETH & BTC Bull Index", "ETHBTC");
        
        // User (EOA) creates the index
        vm.startPrank(user);
        address indexAddress = factory.createIndex(indexImage, initData);
        vm.stopPrank();
        
        return indexAddress;
    }
    
    function _fundIndex(BaseConditionalTokenIndex index) internal {
        // Get the components (conditional token IDs) for this index
        
        console.log("7. Funding index with conditional tokens...");

        uint256[] memory components = index.components();
        
        console.log("Index components:");
        
        // Approve CTF to transfer tokens to index
        vm.startPrank(user);
        CTF.setApprovalForAll(address(index), true);
        index.deposit(INITIAL_FUNDING);
        
        vm.stopPrank();
    }
    
    function _resolveConditions() internal {
        console.log("8. Oracle resolving conditions...");
        
        // Resolve both conditions to YES (outcome 0 wins)
        uint256[] memory payouts1 = new uint256[](OUTCOME_SLOTS);
        payouts1[0] = 1; // YES wins
        payouts1[1] = 0; // NO loses
        
        uint256[] memory payouts2 = new uint256[](OUTCOME_SLOTS);
        payouts2[0] = 1; // YES wins
        payouts2[1] = 0; // NO loses
        
        // Oracle (EOA) resolves the conditions
        vm.startPrank(oracle);
        CTF.reportPayouts(questionId1, payouts1);
        CTF.reportPayouts(questionId2, payouts2);
        vm.stopPrank();
        
        console.log("Conditions resolved by oracle");
        console.log("Condition 1 payout denominator:", CTF.payoutDenominator(conditionId1));
        console.log("Condition 2 payout denominator:", CTF.payoutDenominator(conditionId2));
    }
    
    // function test_RedeemFailsBeforeSolve() public {
    //     _createConditionalTokens();
    //     address indexAddress = _createIndex();
    //     BaseConditionalTokenIndex index = BaseConditionalTokenIndex(indexAddress);
    //     _fundIndex(index);
        
    //     vm.startPrank(user);
    //     vm.expectRevert(BaseConditionalTokenIndex.IndexNotSolvedYet.selector);
    //     index.redeem();
    //     vm.stopPrank();
    // }
    
    // function test_SolveFailsBeforeAllConditionsResolved() public {
    //     _createConditionalTokens();
    //     address indexAddress = _createIndex();
    //     BaseConditionalTokenIndex index = BaseConditionalTokenIndex(indexAddress);
    //     _fundIndex(index);
        
    //     // Try to solve before conditions are resolved
    //     vm.expectRevert(BaseConditionalTokenIndex.NotAllConditionsResolved.selector);
    //     index.solveIndex();
    // }
    
    // function test_CannotDepositOrWithdrawAfterSolve() public {
    //     _createConditionalTokens();
    //     address indexAddress = _createIndex();
    //     BaseConditionalTokenIndex index = BaseConditionalTokenIndex(indexAddress);
    //     _fundIndex(index);
    //     _resolveConditions();
        
    //     index.solveIndex();
        
    //     // Try to deposit after solve
    //     vm.expectRevert(BaseConditionalTokenIndex.CannotDepositAfterSolve.selector);
    //     index.deposit(100);
        
    //     // Try to withdraw after solve
    //     vm.expectRevert(BaseConditionalTokenIndex.CannotWithdrawAfterSolve.selector);
    //     index.withdraw(100);
    // }
}