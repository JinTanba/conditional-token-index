// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import "../src/ConditionalTokensIndexFactory.sol";
import "../src/ConditionalTokensIndex.sol";
import "../src/interfaces/ICTFExchange.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IConditionalTokens} from "../src/interfaces/IConditionalTokens.sol";
import "../src/CTFExchangePriceOracle.sol";

//deploy polygon mainnet:
contract Deploy is Script {
    address polymarket = 0xC5d563A36AE78145C45a50134d48A1215220f80a;
    ICTFExchange ctfExchange = ICTFExchange(polymarket);
    address usdce =0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    IConditionalTokens ctf = IConditionalTokens(0x4D97DCd97eC945f40cF65F87097ACe5EA0476045);
    ConditionalTokensIndexFactory factory;
    ConditionalTokensIndex indexImpl;
    CTFExchangePriceOracle oracle;
    
    function run() public {
        vm.startBroadcast();
        factory = new ConditionalTokensIndexFactory(address(ctf),usdce);
        indexImpl = new ConditionalTokensIndex();
        oracle = new CTFExchangePriceOracle(polymarket,10 minutes,5*10**6);
        console.log("factory");
        console.logAddress(address(factory));
        console.log("indexImpl");
        console.logAddress(address(indexImpl));
        console.log("oracle");
        console.logAddress(address(oracle));
        vm.stopBroadcast();
    }
    
}