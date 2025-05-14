// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./mock/MockConditionalTokens.sol";
import "./mock/MockERC20.sol";

import "../src/ConditionalTokensIndex.sol";
import "../src/BaseConditionalTokenIndex.sol";
import "../src/ConditionalTokensIndexFactory.sol";

contract CTIFlows is Test {
    /* ---------------------------------------------------------------------- */
    /*                               CONSTANTS                                */
    /* ---------------------------------------------------------------------- */
    uint256 private constant FUNDING = 10 ether;
    uint256 private constant MERGE   = 3 ether;      // pulled from each leg

    /* ---------------------------------------------------------------------- */
    /*                            TEST STATE                                  */
    /* ---------------------------------------------------------------------- */
    address alice = address(0xA11CE);

    MockConditionalTokens ctf;
    MockERC20             collateral;
    ConditionalTokensIndex impl;
    ConditionalTokensIndexFactory factory;

    /* ---------------------------------------------------------------------- */
    /*                                SET-UP                                  */
    /* ---------------------------------------------------------------------- */
    function setUp() public {
        vm.startPrank(alice);

        // 1. bootstrap mocks
        ctf        = new MockConditionalTokens();
        collateral = new MockERC20("DAI", "DAI");

        // 2. give Alice some collateral & register two 2-outcome conditions
        collateral.mint(alice, 1_000 ether);

        bytes32 condA = bytes32(uint256(1));
        bytes32 condB = bytes32(uint256(2));
        ctf.setOutcomeSlotCount(condA, 2);
        ctf.setOutcomeSlotCount(condB, 2);

        // 3. deploy implementation + factory
        impl    = new ConditionalTokensIndex();
        factory = new ConditionalTokensIndexFactory(address(ctf), address(collateral));

        // 4. pre-mint every *component* position token Alice will need
        bytes32[] memory cIds = new bytes32[](2);
        uint256[] memory sets = new uint256[](2);
        cIds[0] = condA; sets[0] = 1;
        cIds[1] = condB; sets[1] = 2;

        uint256[] memory comps = _computeComponents(cIds, sets);

        for (uint256 i; i < comps.length; ++i) {
            ctf.mint(alice, comps[i], 100 ether);
        }

        // Alice lets the factory pull her positions
        ctf.setApprovalForAll(address(factory), true);

        vm.stopPrank();
    }

    /* ---------------------------------------------------------------------- */
    /*                          HAPPY-PATH FLOW                               */
    /* ---------------------------------------------------------------------- */
    function test_FullFlow() public {
        // Debug information
        console.log("Starting test_FullFlow");
        vm.startPrank(alice);

        /* --- 1. Build two independent indexes --- */
        console.log("Building two independent indexes");
        (
            address idx1,
            address idx2
        ) = _buildTwoIndexes();
        console.log("Indexes built successfully");
        console.log("idx1:", idx1);
        console.log("idx2:", idx2);

        /* --- 2. Deposit into idx1, then withdraw half --- */
        // First approve the index contract to transfer Alice's position tokens via the CTF contract
        console.log("Setting approval for idx1");
        ctf.setApprovalForAll(address(idx1), true);
        console.log("Depositing to idx1");
        BaseConditionalTokenIndex(idx1).deposit(2 ether);
        console.log("Deposit successful");
        assertEq(BaseConditionalTokenIndex(idx1).balanceOf(alice), FUNDING + 2 ether);

        console.log("Withdrawing from idx1");
        BaseConditionalTokenIndex(idx1).withdraw(1 ether);
        console.log("Withdrawal successful");
        assertEq(BaseConditionalTokenIndex(idx1).balanceOf(alice), FUNDING + 1 ether);

        /* --- 3. Merge idx1 & idx2 into a fresh composite index --- */
        address[] memory legs = new address[](2);
        legs[0] = idx1;
        legs[1] = idx2;

        console.log("Approving idx1 and idx2 for factory");
        BaseConditionalTokenIndex(idx1).approve(address(factory), MERGE);
        BaseConditionalTokenIndex(idx2).approve(address(factory), MERGE);
        console.log("Approvals successful");

        console.log("Merging indexes");
        address merged = factory.mergeIndex(
            address(impl),
            "",                 // specifications
            "",                 // initData
            legs,
            MERGE
        );
        console.log("Merge successful, merged index:", merged);

        // Alice receives freshly minted composite tokens
        assertEq(BaseConditionalTokenIndex(merged).balanceOf(alice), MERGE);

        vm.stopPrank();
    }

    /* ---------------------------------------------------------------------- */
    /*                          INTERNAL HELPERS                              */
    /* ---------------------------------------------------------------------- */

    function _buildTwoIndexes() internal returns (address idx1, address idx2) {
        console.log("Inside _buildTwoIndexes");
        // --- leg-A (cond 1, outcome 1) ---
        {
            bytes32[] memory cond = new bytes32[](1);
            uint256[] memory set = new uint256[](1);
            cond[0] = bytes32(uint256(1));
            set[0]  = 1;

            console.log("Creating first index");
            idx1 = _createIndex(cond, set);
            console.log("First index created:", idx1);
            // Funding goes in & index ERC-20 comes straight back
            assertEq(BaseConditionalTokenIndex(idx1).balanceOf(alice), FUNDING);
            assertEq(ctf.balanceOf(address(factory), _computeComponents(cond, set)[0]), FUNDING);

            // approve leg later
            BaseConditionalTokenIndex(idx1).approve(address(factory), type(uint256).max);
        }

        // --- leg-B (cond 2, outcome 2) ---
        {
            bytes32[] memory cond = new bytes32[](1);
            uint256[] memory set = new uint256[](1);
            cond[0] = bytes32(uint256(2));
            set[0]  = 2;

            console.log("Creating second index");
            idx2 = _createIndex(cond, set);
            console.log("Second index created:", idx2);
            assertEq(BaseConditionalTokenIndex(idx2).balanceOf(alice), FUNDING);
            assertEq(ctf.balanceOf(address(factory), _computeComponents(cond, set)[0]), FUNDING);

            BaseConditionalTokenIndex(idx2).approve(address(factory), type(uint256).max);
        }

        // Return values are named in the function signature
    }

    function _createIndex(
        bytes32[] memory cond,
        uint256[] memory set
    ) internal returns (address) {
        console.log("Inside _createIndex");
        ConditionalTokensIndexFactory.IndexImage memory img = ConditionalTokensIndexFactory
            .IndexImage({
                impl: address(impl),
                conditionIds: cond,
                indexSets: set,
                specifications: ""
            });

        return factory.createIndex(img, "", FUNDING);
    }

    function _computeComponents(
        bytes32[] memory cond,
        uint256[] memory set
    ) internal view returns (uint256[] memory comps) {
        comps = new uint256[](cond.length);
        for (uint256 i; i < cond.length; ++i) {
            bytes32 col = ctf.getCollectionId(bytes32(0), cond[i], set[i]);
            comps[i]    = ctf.getPositionId(address(collateral), col);
        }
        // Assembly-free insertion sort (n ≤ 3 in these tests)
        for (uint256 i; i < comps.length; ++i) {
            for (uint256 j = i + 1; j < comps.length; ++j) {
                if (comps[j] < comps[i]) (comps[i], comps[j]) = (comps[j], comps[i]);
            }
        }
    }
}
