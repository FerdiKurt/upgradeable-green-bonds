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
    
