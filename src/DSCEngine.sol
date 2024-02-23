// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title DSCEngine
 * @author Robbyn
 *
 * The system is designed to be as minimalistic, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {
    ////////////////
    // Errors     //
    ////////////////
    error DSCEngine__AmountMustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__MintFailed();
    error DSCEngine__InvalidHealthFactor(uint256 healtFactor);

    /////////////////////////
    // State Variables     //
    /////////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds; // token to price feed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 dscToken) private s_DSCMinted;
    address[] private s_collateralTokens;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISSION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISSION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    DecentralizedStableCoin private immutable i_dsc; // DecentralizedStableCoin = DSC

    ////////////////
    // Events     //
    ////////////////
    event CollateralDeposited(address indexed user, address indexed tokenCollateralAddress, uint256 amountCollateral);
    event CollateralRedeemed(address indexed user, address indexed tokenCollateralAddress, uint256 amountCollateral);

    ////////////////
    // Modifiers  //
    ////////////////
    modifier amountMoreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__AmountMustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    ////////////////
    // Functions  //
    ////////////////
    constructor(address[] memory _tokenAddresses, address[] memory _priceFeedAddresses) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
        }
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_collateralTokens.push(_tokenAddresses[i]);
        }
        i_dsc = new DecentralizedStableCoin(address(this));
    }

    /////////////////////////
    // External Functions  //
    /////////////////////////
    /**
     *
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount od collateral to deposit
     * @param amountDscToMint the amount of DSC to mint
     * @notice this function will execute deposit collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /**
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        amountMoreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @param amountDscToMint the amount of DSC to mint
     * @notice the value of collateral must be higher than the minimum threshold
     */
    function mintDSC(uint256 amountDscToMint) public amountMoreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _validateHealthFactor(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }
    /**
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to redeem
     * @param amountDscToBurn the amount of DSC to burn
     * @notice this function will execute burn DSC and redeem underlying collateral one transaction
     */

    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /**
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to redeem
     * 
     * Note: Health factor must be higher than 1 after the collateral is redeemed
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        amountMoreThanZero(amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _validateHealthFactor(msg.sender);
    }

    // Do we need to check if health factor is valid?
    function burnDSC(uint256 amountDscToBurn) public amountMoreThanZero(amountDscToBurn) {
        s_DSCMinted[msg.sender] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(msg.sender, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
        _validateHealthFactor(msg.sender); // I don't think this will ever happen
    }

    function liquidate() external {}

    function getHealtFactor() external {}

    /////////////////////////////////////
    // Internal and Private Functions  //
    /////////////////////////////////////
    /**
     * @param user the address of user
     * Return how close user on liquidation
     * If the result is less than 1, user will be liquidated
     */
    function _healtFactor(address user) private view returns (uint256) {
        // total DSC Minted
        // total collateral value
        (uint256 totalDSCMinted, uint256 totalCollateralValueInUSD) = _getAccountInformation(user);

        if (totalDSCMinted == 0) return type(uint256).max;
        uint256 totalCollateralAdjustedByThreshold =
            totalCollateralValueInUSD * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISSION;
        // 1000$ ETH / 200 DSC
        // 1000 * 50 / 100 = 500 => 500 / 200 > 1
        return totalCollateralAdjustedByThreshold * PRECISSION / totalDSCMinted;
    }

    /**
     * 1. Chack if user have enough collateral value (using healt factor)
     * 2. Revert if it doesn't
     */
    function _validateHealthFactor(address user) internal view {
        uint256 healthFactor = _healtFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__InvalidHealthFactor(healthFactor);
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValueInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        totalCollateralValueInUSD = getAccountCollateralValue(user);
    }

    ////////////////////////////////
    // Public and View Functions  //
    ////////////////////////////////
    function getUSDValueBasedOnPriceFeed(address token, uint256 amount) public view returns (uint256 valueInUSD) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISSION;
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValueBasedOnPriceFeed(token, amount);
        }
    }

    function getDecentralizedStableCoinContractAddress() external view returns (address) {
        return address(i_dsc);
    }
}
