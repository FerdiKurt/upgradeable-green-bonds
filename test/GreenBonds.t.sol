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
    
    // Test coupon claiming
    function testClaimCoupon() public {
        uint256 bondAmount = 10;
        
        // Purchase bonds
        vm.prank(investor1);
        greenBonds.purchaseBonds(bondAmount);
        
        // Fast forward time
        vm.warp(block.timestamp + 365 days);
        
        uint256 claimableAmount = greenBonds.calculateClaimableCoupon(investor1);
        assertTrue(claimableAmount > 0);
        
        uint256 balanceBefore = paymentToken.balanceOf(investor1);
        
        vm.expectEmit(true, true, true, true);
        emit CouponClaimed(investor1, claimableAmount);
        
        vm.prank(investor1);
        greenBonds.claimCoupon();
        
        uint256 balanceAfter = paymentToken.balanceOf(investor1);
        assertEq(balanceAfter - balanceBefore, claimableAmount);
    }
    
    function testClaimCouponFailures() public {
        // Test no bonds
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.NoCouponAvailable.selector);
        greenBonds.claimCoupon();
        
        // Purchase bonds but no time passed
        vm.prank(investor1);
        greenBonds.purchaseBonds(10);
        
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.NoCouponAvailable.selector);
        greenBonds.claimCoupon();
    }
    
    // Test bond redemption
    function testRedeemBonds() public {
        uint256 bondAmount = 10;
        
        // Purchase bonds
        vm.prank(investor1);
        greenBonds.purchaseBonds(bondAmount);
        
        // Fast forward to maturity
        vm.warp(block.timestamp + MATURITY_PERIOD + 1);
        
        uint256 balanceBefore = paymentToken.balanceOf(investor1);
        uint256 expectedPrincipal = bondAmount * FACE_VALUE;
        
        vm.expectEmit(true, true, true, true);
        emit BondRedeemed(investor1, bondAmount, expectedPrincipal);
        
        vm.prank(investor1);
        greenBonds.redeemBonds();
        
        assertEq(greenBonds.balanceOf(investor1), 0);
        assertTrue(paymentToken.balanceOf(investor1) >= balanceBefore + expectedPrincipal);
    }
    
    function testRedeemBondsFailures() public {
        // Test before maturity
        vm.prank(investor1);
        greenBonds.purchaseBonds(10);
        
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.BondNotMatured.selector);
        greenBonds.redeemBonds();
        
        // Test no bonds
        vm.warp(block.timestamp + MATURITY_PERIOD + 1);
        vm.prank(investor2);
        vm.expectRevert(UpgradeableGreenBonds.NoBondsToRedeem.selector);
        greenBonds.redeemBonds();
    }
    
    // Test early redemption
    function testEarlyRedemption() public {
        uint256 bondAmount = 10;
        
        // Enable early redemption
        vm.prank(issuer);
        greenBonds.setEarlyRedemptionParams(true, 300); // 3% penalty
        
        // Purchase bonds
        vm.prank(investor1);
        greenBonds.purchaseBonds(bondAmount);
        
        uint256 redemptionValue = bondAmount * FACE_VALUE;
        uint256 penalty = redemptionValue * 300 / 10000;
        uint256 expectedPayout = redemptionValue - penalty;
        
        vm.expectEmit(true, true, true, true);
        emit BondRedeemedEarly(investor1, bondAmount, expectedPayout, penalty);
        
        vm.prank(investor1);
        greenBonds.redeemBondsEarly(bondAmount);
        
        assertEq(greenBonds.balanceOf(investor1), 0);
    }
    
    function testEarlyRedemptionFailures() public {
        vm.prank(investor1);
        greenBonds.purchaseBonds(10);
        
        // Test when disabled
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.EarlyRedemptionNotEnabled.selector);
        greenBonds.redeemBondsEarly(5);
        
        // Enable and test invalid amount
        vm.prank(issuer);
        greenBonds.setEarlyRedemptionParams(true, 300);
        
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.InvalidBondAmount.selector);
        greenBonds.redeemBondsEarly(0);
        
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.InvalidBondAmount.selector);
        greenBonds.redeemBondsEarly(20); // More than owned
    }
    
    // Test tranches
    function testAddTranche() public {
        string memory trancheName = "Senior Tranche";
        uint256 trancheFaceValue = 2000 * 10**18;
        uint256 trancheCouponRate = 400; // 4%
        uint256 seniority = 1;
        uint256 trancheSupply = 1000;
        
        vm.expectEmit(true, true, true, true);
        emit TrancheAdded(0, trancheName, trancheCouponRate, seniority);
        
        vm.prank(issuer);
        greenBonds.addTranche(trancheName, trancheFaceValue, trancheCouponRate, seniority, trancheSupply);
        
        assertEq(greenBonds.trancheCount(), 1);
        
        (string memory name, uint256 faceValue, uint256 couponRate, uint256 sen, uint256 totalSupply, uint256 availableSupply) = 
            greenBonds.getTrancheDetails(0);
        
        assertEq(name, trancheName);
        assertEq(faceValue, trancheFaceValue);
        assertEq(couponRate, trancheCouponRate);
        assertEq(sen, seniority);
        assertEq(totalSupply, trancheSupply);
        assertEq(availableSupply, trancheSupply);
    }
    
    function testPurchaseTrancheBonds() public {
        // Add tranche first
        vm.prank(issuer);
        greenBonds.addTranche("Senior", 2000 * 10**18, 400, 1, 1000);
        
        uint256 bondAmount = 5;
        uint256 trancheId = 0;
        
        vm.prank(investor1);
        greenBonds.purchaseTrancheBonds(trancheId, bondAmount);
        
        assertEq(greenBonds.getTrancheHoldings(trancheId, investor1), bondAmount);
    }
    
    function testTransferTrancheBonds() public {
        // Setup tranche and purchase
        vm.prank(issuer);
        greenBonds.addTranche("Senior", 2000 * 10**18, 400, 1, 1000);
        
        vm.prank(investor1);
        greenBonds.purchaseTrancheBonds(0, 10);
        
        // Transfer bonds
        vm.prank(investor1);
        greenBonds.transferTrancheBonds(0, investor2, 5);
        
        assertEq(greenBonds.getTrancheHoldings(0, investor1), 5);
        assertEq(greenBonds.getTrancheHoldings(0, investor2), 5);
    }
    
    // Test impact reports
    function testAddImpactReport() public {
        string memory reportURI = "https://example.com/report1";
        string memory reportHash = "0x123456789abcdef";
        string memory metricsJson = '{"co2_reduction": 1000, "energy_generated": 5000}';
        string[] memory metricNames = new string[](2);
        metricNames[0] = "co2_reduction";
        metricNames[1] = "energy_generated";
        uint256[] memory metricValues = new uint256[](2);
        metricValues[0] = 1000;
        metricValues[1] = 5000;
        
        vm.expectEmit(true, true, true, true);
        emit ImpactReportAdded(0, reportURI);
        
        vm.prank(issuer);
        greenBonds.addImpactReport(
            reportURI,
            reportHash,
            metricsJson,
            metricNames,
            metricValues,
            7 days,
            2
        );
        
        assertEq(greenBonds.getImpactReportCount(), 1);
        assertEq(greenBonds.getImpactMetricValue(0, "co2_reduction"), 1000);
        assertEq(greenBonds.getImpactMetricValue(0, "energy_generated"), 5000);
    }
    
    function testVerifyImpactReport() public {
        // Add report first
        string[] memory metricNames = new string[](1);
        metricNames[0] = "co2_reduction";
        uint256[] memory metricValues = new uint256[](1);
        metricValues[0] = 1000;
        
        vm.prank(issuer);
        greenBonds.addImpactReport(
            "https://example.com/report",
            "0x123",
            "{}",
            metricNames,
            metricValues,
            7 days,
            1 // Only need 1 verification
        );
        
        uint256 oldRate = greenBonds.couponRate();
        
        vm.expectEmit(true, true, true, true);
        emit ImpactReportVerified(0, verifier);
        
        vm.prank(verifier);
        greenBonds.verifyImpactReport(0);
        
        // Should increase coupon rate
        assertTrue(greenBonds.couponRate() > oldRate);
    }
    
    function testChallengeImpactReport() public {
        // Add report and verify
        string[] memory metricNames = new string[](1);
        metricNames[0] = "co2_reduction";
        uint256[] memory metricValues = new uint256[](1);
        metricValues[0] = 1000;
        
        vm.prank(issuer);
        greenBonds.addImpactReport(
            "https://example.com/report",
            "0x123",
            "{}",
            metricNames,
            metricValues,
            7 days,
            2
        );
        
        // Add another verifier
        vm.prank(admin);
        greenBonds.addVerifier(address(0x8));
        
        // First verification
        vm.prank(verifier);
        greenBonds.verifyImpactReport(0);
        
        // Challenge the report
        vm.prank(address(0x8));
        greenBonds.challengeImpactReport(0, "Metrics appear inflated");
        
        // Verification count should be reset
        address[] memory verifiers = greenBonds.getReportVerifiers(0);
        assertEq(verifiers.length, 0);
    }
    
    // Test governance
    function testCreateProposal() public {
        string memory description = "Update coupon rate";
        address target = address(greenBonds);
        bytes memory callData = abi.encodeWithSelector(
            greenBonds.updateCouponPeriod.selector,
            60 days
        );
        
        vm.expectEmit(true, true, true, true);
        emit ProposalCreated(0, issuer, description);
        
        vm.prank(issuer);
        uint256 proposalId = greenBonds.createProposal(description, target, callData);
        
        assertEq(proposalId, 0);
        assertEq(greenBonds.proposalCount(), 1);
    }
    
    function testVoteOnProposal() public {
        // Create proposal
        vm.prank(issuer);
        uint256 proposalId = greenBonds.createProposal("Test", address(0), "");
        
        // Purchase bonds to get voting power
        vm.prank(investor1);
        greenBonds.purchaseBonds(100);
        
        vm.expectEmit(true, true, true, true);
        emit VoteCast(investor1, proposalId, true, 100);
        
        vm.prank(investor1);
        greenBonds.castVote(proposalId, true);
    }
    
    function testExecuteProposal() public {
        // First, grant ISSUER_ROLE to the contract itself so it can execute the proposal
        vm.prank(admin);
        greenBonds.grantRole(greenBonds.ISSUER_ROLE(), address(greenBonds));
        
        bytes memory callData = abi.encodeWithSelector(
            greenBonds.addGreenCertification.selector,
            "New Green Certification"
        );
        
        vm.prank(issuer);
        uint256 proposalId = greenBonds.createProposal("Add certification", address(greenBonds), callData);
        
        // Get enough voting power (30% of 10,000 total supply = 3,000 bonds minimum for quorum)
        vm.prank(investor1);
        greenBonds.purchaseBonds(3500); // Buy 3,500 bonds to exceed quorum
        
        // Vote in favor
        vm.prank(investor1);
        greenBonds.castVote(proposalId, true);
        
        // Fast forward past voting period
        vm.warp(block.timestamp + 8 days);
        
        // Execute proposal
        vm.prank(investor1);
        greenBonds.executeProposal(proposalId);
        
        // Verify the change took effect
        assertEq(greenBonds.getGreenCertificationCount(), 1);
        
        // Verify proposal is marked as executed
        (address proposer, , , address target, uint256 forVotes, uint256 againstVotes, , uint256 endTime, bool executed) = greenBonds.proposals(proposalId);
        assertTrue(executed);
        assertTrue(block.timestamp > endTime);
        assertEq(proposer, issuer);
        assertTrue(forVotes > againstVotes);
        assertEq(target, address(greenBonds));
    }

    function testExecuteProposalWithTimelock() public {
        // Grant contract ISSUER_ROLE so it can execute the proposal
        vm.prank(admin);
        greenBonds.grantRole(greenBonds.ISSUER_ROLE(), address(greenBonds));
        
        uint256 originalPeriod = greenBonds.couponPeriod(); // 30 days
        
        // Test 1: Direct call with proper timelock flow
        // First call: Schedule the operation
        vm.prank(issuer);
        greenBonds.updateCouponPeriod(60 days);
        
        // Value should remain unchanged (operation scheduled, not executed)
        assertEq(greenBonds.couponPeriod(), originalPeriod);
        
        // Try to execute before timelock expires (should fail)
        vm.prank(issuer);
        vm.expectRevert(UpgradeableGreenBonds.TimelockNotExpired.selector);
        greenBonds.updateCouponPeriod(60 days);
        
        // Fast forward past timelock period (2 days)
        vm.warp(block.timestamp + 3 days);
        
        // Second call: Execute the scheduled operation
        vm.prank(issuer);
        greenBonds.updateCouponPeriod(60 days);
        
        // Now the value should be updated
        assertEq(greenBonds.couponPeriod(), 60 days);
        
        // Try to execute the same operation again (should fail)
        vm.prank(issuer);
        vm.expectRevert(UpgradeableGreenBonds.OperationAlreadyExecuted.selector);
        greenBonds.updateCouponPeriod(60 days);
        
        // Test 2: Governance proposal with timelock
        bytes memory callData = abi.encodeWithSelector(
            greenBonds.updateCouponPeriod.selector,
            90 days
        );
        
        vm.prank(issuer);
        uint256 proposalId = greenBonds.createProposal(
            "Update coupon period to 90 days", 
            address(greenBonds), 
            callData
        );
        
        // Setup voting
        vm.prank(investor1);
        greenBonds.purchaseBonds(3500); // 35% of total supply for quorum
        
        vm.prank(investor1);
        greenBonds.castVote(proposalId, true);
        
        // Fast forward past voting period
        vm.warp(block.timestamp + 8 days);
        
        // Execute proposal - this will SCHEDULE the updateCouponPeriod operation
        vm.prank(investor1);
        greenBonds.executeProposal(proposalId);
        
        // Value should still be 60 days (governance scheduled the operation)
        assertEq(greenBonds.couponPeriod(), 60 days);
        
        // Verify proposal is marked as executed
        (, , , , , , , , bool executed) = greenBonds.proposals(proposalId);
        assertTrue(executed);
        
        // Fast forward past timelock period for governance operation
        vm.warp(block.timestamp + 3 days);
        
        // Now trigger the scheduled governance operation
        // Note: This needs to be called by someone with ISSUER_ROLE
        // The contract itself has been granted this role for governance execution
        vm.prank(address(greenBonds));
        greenBonds.updateCouponPeriod(90 days);
        
        // Now the governance operation should be executed
        assertEq(greenBonds.couponPeriod(), 90 days);
        
        // Test 3: same operationId should fail
        vm.prank(address(greenBonds));
        vm.expectRevert(UpgradeableGreenBonds.OperationAlreadyExecuted.selector);
        greenBonds.updateCouponPeriod(90 days);
        
        // Test 4: Schedule a new operation with different parameters
        vm.prank(issuer);
        greenBonds.updateCouponPeriod(120 days); // Different value = different operationId
        
        // Should still be 90 days (new operation scheduled)
        assertEq(greenBonds.couponPeriod(), 90 days);
        
        // Fast forward and execute
        vm.warp(block.timestamp + 3 days);
        vm.prank(issuer);
        greenBonds.updateCouponPeriod(120 days);
        
        // Should now be updated
        assertEq(greenBonds.couponPeriod(), 120 days);
        
        // Final verification
        assertEq(greenBonds.proposalCount(), 1);
    }    
    
    // Test fund management
    function testWithdrawProjectFunds() public {
        // Purchase bonds to create project funds
        vm.prank(investor1);
        greenBonds.purchaseBonds(100);
        
        (,, uint256 projectFundsBefore,,) = greenBonds.getTreasuryStatus();
        assertTrue(projectFundsBefore > 0);
        
        uint256 withdrawAmount = projectFundsBefore / 2;
        
        vm.expectEmit(true, true, true, true);
        emit FundWithdrawal(treasurer, withdrawAmount, "Solar panels", block.timestamp);
        
        vm.prank(treasurer);
        greenBonds.withdrawProjectFunds(treasurer, withdrawAmount, "Solar panels");
        
        (,, uint256 projectFundsAfter,,) = greenBonds.getTreasuryStatus();
        assertEq(projectFundsAfter, projectFundsBefore - withdrawAmount);
    }
    
