// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC public deployer;
    DecentralizedStableCoin public dscCoin;
    DSCEngine public dscEngine;
    HelperConfig public helperConfig;

    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant ETH_USD_PRICE = 2000;
    uint256 public constant BTC_USD_PRICE = 1000;

    address USER = makeAddr("user");
    address USER_2 = makeAddr("user2");

    function setUp() public {
        deployer = new DeployDSC();
        (dscCoin, dscEngine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
    }

    // modifier validEnv {
    //   if (block.chainid )
    // }

    ////////////////////
    // Price Test     //
    ////////////////////
    function testUSDValueBasedOnPriceFeed() public {
        uint256 ethAmount = 15e18;
        // 15e18 ETH * ETH Price ($2000/ETH) = 30_000e18
        uint256 expectedValue = ethAmount * ETH_USD_PRICE;
        uint256 actualValue = dscEngine.getUSDValueBasedOnPriceFeed(weth, ethAmount);
        assertEq(expectedValue, actualValue);
    }

    /////////////////////////
    // Collateral Test     //
    /////////////////////////
    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        // ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}
