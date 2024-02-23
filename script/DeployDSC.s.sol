// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin dscCoin, DSCEngine dscEngine, HelperConfig helperConfig) {
        helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);

        dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses);
        // set up DecentralizedStableCoin contract with created contract from DSCEngine
        dscCoin = DecentralizedStableCoin(dscEngine.getDecentralizedStableCoinContractAddress());

        vm.stopBroadcast();
    }
}
