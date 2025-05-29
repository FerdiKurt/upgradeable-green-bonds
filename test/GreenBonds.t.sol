// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/GreenBonds.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 100000000 * 10**18); // Mint 100M tokens
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

    UpgradeableGreenBonds public greenBonds;
    UpgradeableGreenBonds public implementation;
    MockERC20 public paymentToken;
    ERC1967Proxy public proxy;
    
    address public admin = address(0x1);
    address public issuer = address(0x2);
    address public verifier = address(0x3);
    address public treasurer = address(0x4);
    address public investor1 = address(0x5);
    address public investor2 = address(0x6);
    address public upgrader = address(0x7);
    
    // Bond parameters
    string constant BOND_NAME = "Green Energy Bond";
    string constant BOND_SYMBOL = "GEB";
    uint256 constant FACE_VALUE = 1000 * 10**18; // 1000 tokens
    uint256 constant TOTAL_SUPPLY = 10000; // 10,000 bonds
    uint256 constant BASE_COUPON_RATE = 500; // 5%
    uint256 constant MAX_COUPON_RATE = 1000; // 10%
    uint256 constant COUPON_PERIOD = 30 days;
    uint256 constant MATURITY_PERIOD = 365 days;
    string constant PROJECT_DESCRIPTION = "Solar farm development";
    string constant IMPACT_METRICS = "CO2 reduction, energy generation";
    
    event BondPurchased(address indexed investor, uint256 amount, uint256 tokensSpent);
    event CouponClaimed(address indexed investor, uint256 amount);
    event BondRedeemed(address indexed investor, uint256 amount, uint256 tokensReceived);
    event ImpactReportAdded(uint256 indexed reportId, string reportURI);
    event ImpactReportVerified(uint256 indexed reportId, address verifier);
    event ImpactReportFinalized(uint256 indexed reportId);
    event CouponRateUpdated(uint256 newRate);
    event BondMaturityReached(uint256 maturityDate);
    event TrancheAdded(uint256 indexed trancheId, string name, uint256 couponRate, uint256 seniority);
    event ProposalCreated(uint256 indexed proposalId, address proposer, string description);
    event VoteCast(address indexed voter, uint256 indexed proposalId, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event EarlyRedemptionStatusChanged(bool enabled);
    event BondRedeemedEarly(address indexed investor, uint256 amount, uint256 tokensReceived, uint256 penalty);
    event EmergencyRecovery(address indexed recipient, uint256 amount);
    event FundWithdrawal(address indexed recipient, uint256 amount, string category, uint256 timestamp);
    
    function setUp() public {
        // Deploy mock payment token
        paymentToken = new MockERC20("USD Coin", "USDC");
        
        // Deploy implementation
        implementation = new UpgradeableGreenBonds();
        
        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            UpgradeableGreenBonds.initialize.selector,
            BOND_NAME,
            BOND_SYMBOL,
            FACE_VALUE,
            TOTAL_SUPPLY,
            BASE_COUPON_RATE,
            MAX_COUPON_RATE,
            COUPON_PERIOD,
            MATURITY_PERIOD,
            address(paymentToken),
            PROJECT_DESCRIPTION,
            IMPACT_METRICS
        );
        
        // Deploy proxy with initialization
        proxy = new ERC1967Proxy(address(implementation), initData);
        greenBonds = UpgradeableGreenBonds(address(proxy));
        
        // Setup roles
        vm.startPrank(address(this)); // Default admin is deployer
        greenBonds.grantRole(greenBonds.DEFAULT_ADMIN_ROLE(), admin);
        greenBonds.grantRole(greenBonds.ISSUER_ROLE(), issuer);
        greenBonds.grantRole(greenBonds.VERIFIER_ROLE(), verifier);
        greenBonds.grantRole(greenBonds.TREASURY_ROLE(), treasurer);
        greenBonds.grantRole(greenBonds.UPGRADER_ROLE(), upgrader);
        vm.stopPrank();
        
        // Distribute payment tokens
        paymentToken.transfer(investor1, 10000000 * 10**18);
        paymentToken.transfer(investor2, 10000000 * 10**18);
        
        // Approve spending
        vm.prank(investor1);
        paymentToken.approve(address(greenBonds), type(uint256).max);
        vm.prank(investor2);
        paymentToken.approve(address(greenBonds), type(uint256).max);
    }
    
    // Test initialization
    function testInitialization() public view {
        assertEq(greenBonds.bondName(), BOND_NAME);
        assertEq(greenBonds.bondSymbol(), BOND_SYMBOL);
        assertEq(greenBonds.faceValue(), FACE_VALUE);
        assertEq(greenBonds.bondTotalSupply(), TOTAL_SUPPLY);
        assertEq(greenBonds.availableSupply(), TOTAL_SUPPLY);
        assertEq(greenBonds.baseCouponRate(), BASE_COUPON_RATE);
        assertEq(greenBonds.couponRate(), BASE_COUPON_RATE);
        assertEq(greenBonds.maxCouponRate(), MAX_COUPON_RATE);
        assertEq(greenBonds.couponPeriod(), COUPON_PERIOD);
        assertEq(address(greenBonds.paymentToken()), address(paymentToken));
        assertEq(greenBonds.projectDescription(), PROJECT_DESCRIPTION);
        assertEq(greenBonds.impactMetrics(), IMPACT_METRICS);
    }
    
    // Test bond purchase
    function testPurchaseBonds() public {
        uint256 bondAmount = 10;
        uint256 cost = bondAmount * FACE_VALUE;
        
        vm.expectEmit(true, true, true, true);
        emit BondPurchased(investor1, bondAmount, cost);
        
        vm.prank(investor1);
        greenBonds.purchaseBonds(bondAmount);
        
        assertEq(greenBonds.balanceOf(investor1), bondAmount);
        assertEq(greenBonds.availableSupply(), TOTAL_SUPPLY - bondAmount);
        
        // Check treasury allocation
        (uint256 principal, uint256 coupon, uint256 project, uint256 emergency, ) = greenBonds.getTreasuryStatus();
        assertTrue(principal > 0);
        assertTrue(coupon > 0);
        assertTrue(project > 0);
        assertTrue(emergency > 0);
    }
    
    function testPurchaseBondsFailures() public {
        // Test zero amount
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.InvalidBondAmount.selector);
        greenBonds.purchaseBonds(0);
        
        // Test insufficient supply
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.InsufficientBondsAvailable.selector);
        greenBonds.purchaseBonds(TOTAL_SUPPLY + 1);
        
        // Test after maturity
        vm.warp(block.timestamp + MATURITY_PERIOD + 1);
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.BondMatured.selector);
        greenBonds.purchaseBonds(1);
    }
