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
    
    function testEmergencyRecovery() public {
        // Add some funds to contract for recovery
        paymentToken.transfer(address(greenBonds), 1000 * 10**18);
        
        uint256 recoveryAmount = 500 * 10**18;
        uint256 contractBalanceBefore = paymentToken.balanceOf(address(greenBonds));
        uint256 adminBalanceBefore = paymentToken.balanceOf(admin);
        
        // First call: Schedule the operation
        // Should emit OperationScheduled event
        vm.prank(admin);
        greenBonds.emergencyRecovery(admin, recoveryAmount);
        
        // Balances unchanged (operation scheduled)
        assertEq(paymentToken.balanceOf(address(greenBonds)), contractBalanceBefore);
        assertEq(paymentToken.balanceOf(admin), adminBalanceBefore);
        
        // Try to execute before timelock expires (should fail)
        vm.prank(admin);
        vm.expectRevert(UpgradeableGreenBonds.TimelockNotExpired.selector);
        greenBonds.emergencyRecovery(admin, recoveryAmount);
        
        // Fast forward past timelock period
        vm.warp(block.timestamp + 3 days);
        
        // Second call: Execute the operation
        // Should emit both EmergencyRecovery and OperationExecuted events
        vm.expectEmit(true, true, true, true);
        emit EmergencyRecovery(admin, recoveryAmount);
        
        vm.prank(admin);
        greenBonds.emergencyRecovery(admin, recoveryAmount);
        
        // Balances should now be updated
        assertEq(paymentToken.balanceOf(address(greenBonds)), contractBalanceBefore - recoveryAmount);
        assertEq(paymentToken.balanceOf(admin), adminBalanceBefore + recoveryAmount);
        
        // Try to execute again (should fail)
        vm.prank(admin);
        vm.expectRevert(UpgradeableGreenBonds.OperationAlreadyExecuted.selector);
        greenBonds.emergencyRecovery(admin, recoveryAmount);
    }
    
    // Test access control
    function testAccessControl() public {
        // Test unauthorized access
        vm.prank(investor1);
        vm.expectRevert();
        greenBonds.addTranche("Test", 1000, 100, 1, 100);
        
        vm.prank(investor1);
        vm.expectRevert();
        greenBonds.addVerifier(address(0x9));
        
        vm.prank(investor1);
        vm.expectRevert();
        greenBonds.pause();
    }
    
    // Test pausable functionality
    function testPausable() public {
        vm.prank(admin);
        greenBonds.pause();
        
        vm.prank(investor1);
        vm.expectRevert();
        greenBonds.purchaseBonds(1);
        
        vm.prank(admin);
        greenBonds.unpause();
        
        // Should work after unpause
        vm.prank(investor1);
        greenBonds.purchaseBonds(1);
    }

    function testPausableWithSpecificErrors() public {
        // Test pausable functionality with specific custom error checking
        
        // First, let's purchase a bond so we can test claim functionality
        vm.prank(investor1);
        greenBonds.purchaseBonds(10);
        
        // Pause the contract
        vm.prank(admin);
        greenBonds.pause();
        
        // Test specific operations that should fail with EnforcedPause
        
        // Purchase bonds
        vm.prank(investor1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        greenBonds.purchaseBonds(1);
        
        // Claim coupon  
        vm.prank(investor1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        greenBonds.claimCoupon();
        
        // Add tranche
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        greenBonds.addTranche("Test Tranche", 1000, 100, 1, 100);
        
        // Add impact report
        string[] memory metricNames = new string[](1);
        metricNames[0] = "test_metric";
        uint256[] memory metricValues = new uint256[](1);
        metricValues[0] = 100;
        
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        greenBonds.addImpactReport(
            "test_uri", 
            "test_hash", 
            "{}", 
            metricNames, 
            metricValues, 
            7 days, 
            1
        );
        
        // Withdraw project funds
        vm.prank(treasurer);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        greenBonds.withdrawProjectFunds(treasurer, 1000, "test");
        
        // Update coupon period
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        greenBonds.updateCouponPeriod(45 days);
        
        // Unpause the contract
        vm.prank(admin);
        greenBonds.unpause();
        
        // Verify operations work after unpause
        vm.prank(investor1);
        greenBonds.purchaseBonds(1);
        assertEq(greenBonds.balanceOf(investor1), 11); // 10 + 1
        
        vm.prank(issuer);
        greenBonds.addTranche("Working Tranche", 2000, 200, 2, 500);
        assertEq(greenBonds.trancheCount(), 1);
    }
    
    // Test maturity event emission
    function testMaturityEventEmission() public {
        // Purchase some bonds
        vm.prank(investor1);
        greenBonds.purchaseBonds(10);
        
        // Fast forward to maturity
        vm.warp(block.timestamp + MATURITY_PERIOD + 1);
        
        vm.expectEmit(true, true, true, true);
        emit BondMaturityReached(block.timestamp - 1);
        
        // Maturity event should be emitted on next interaction
        vm.prank(investor1);
        greenBonds.redeemBonds();
    }
    
    // Test allocation percentage updates
    function testUpdateAllocationPercentages() public {
        vm.prank(admin);
        greenBonds.updateAllocationPercentages(5000, 4000, 1000); // 50%, 40%, 10%
        
        (uint256 principal, uint256 project, uint256 emergency) = greenBonds.getAllocationPercentages();
        assertEq(principal, 5000);
        assertEq(project, 4000);
        assertEq(emergency, 1000);
    }
    
    // Test green certifications
    function testAddGreenCertification() public {
        vm.prank(issuer);
        greenBonds.addGreenCertification("LEED Gold");
        
        assertEq(greenBonds.getGreenCertificationCount(), 1);
    }
    
    // Test version
    function testVersion() public view {
        assertEq(greenBonds.version(), "v1.0.0");
    }
    
    // Test edge cases and boundary conditions
    function testCalculateInterestEdgeCases() public {
        // Purchase bonds
        vm.prank(investor1);
        greenBonds.purchaseBonds(1);
        
        // Test immediately after purchase (should be 0)
        uint256 interest = greenBonds.calculateClaimableCoupon(investor1);
        assertEq(interest, 0);
        
        // Test after 1 second
        vm.warp(block.timestamp + 1);
        interest = greenBonds.calculateClaimableCoupon(investor1);
        assertTrue(interest > 0);
    }
    
    // Test ERC20 transfer overrides
    function testERC20TransferOverrides() public {
        vm.prank(investor1);
        greenBonds.purchaseBonds(10);
        
        // Transfer to investor2
        vm.prank(investor1);
        greenBonds.transfer(investor2, 5);
        
        assertEq(greenBonds.balanceOf(investor1), 5);
        assertEq(greenBonds.balanceOf(investor2), 5);
        
        // investor2 should have coupon claim date set
        assertTrue(greenBonds.lastCouponClaimDate(investor2) > 0);
    }
    
    // Test error scenarios
    function testComprehensiveErrorScenarios() public {     
        // Test invalid tranche operations
        vm.expectRevert(UpgradeableGreenBonds.TrancheDoesNotExist.selector);
        greenBonds.getTrancheDetails(999);
        
        vm.expectRevert(UpgradeableGreenBonds.TrancheDoesNotExist.selector);
        vm.prank(investor1);
        greenBonds.purchaseTrancheBonds(999, 1);
        
        // Test invalid report operations WITH proper authorization
        vm.prank(verifier); // Use authorized account
        vm.expectRevert(UpgradeableGreenBonds.ReportDoesNotExist.selector);
        greenBonds.verifyImpactReport(999);
        
        // Test report view functions (no auth required)
        vm.expectRevert(UpgradeableGreenBonds.ReportDoesNotExist.selector);
        greenBonds.getImpactMetricValue(999, "test");
        
        vm.expectRevert(UpgradeableGreenBonds.ReportDoesNotExist.selector);
        greenBonds.getImpactMetricNames(999);
        
        // Test invalid proposal operations
        vm.expectRevert(UpgradeableGreenBonds.ProposalDoesNotExist.selector);
        vm.prank(investor1);
        greenBonds.castVote(999, true);
        
        vm.expectRevert(UpgradeableGreenBonds.ProposalDoesNotExist.selector);
        vm.prank(investor1);
        greenBonds.executeProposal(999);
    }

    function testInvalidParameterErrors() public {
        // Invalid bond amounts
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.InvalidBondAmount.selector);
        greenBonds.purchaseBonds(0);
        
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.InsufficientBondsAvailable.selector);
        greenBonds.purchaseBonds(TOTAL_SUPPLY + 1);
        
        // Invalid tranche parameters
        vm.prank(issuer);
        vm.expectRevert(UpgradeableGreenBonds.EmptyString.selector);
        greenBonds.addTranche("", 1000, 100, 1, 100); // Empty name
        
        vm.prank(issuer);
        vm.expectRevert(UpgradeableGreenBonds.InvalidValue.selector);
        greenBonds.addTranche("Test", 0, 100, 1, 100); // Zero face value
        
        // Invalid allocation percentages
        vm.prank(admin);
        vm.expectRevert(UpgradeableGreenBonds.InvalidValue.selector);
        greenBonds.updateAllocationPercentages(5000, 4000, 2000); // Sum > 100%
    }
    
    // Test bulk operations with large purchase
    function testGasOptimization() public {
        vm.prank(investor1);
        greenBonds.purchaseBonds(1000); // Large purchase
        
        // Fast forward and claim large coupon
        vm.warp(block.timestamp + 365 days);
        
        vm.prank(investor1);
        greenBonds.claimCoupon();
        
        // Test large redemption
        vm.warp(block.timestamp + MATURITY_PERIOD);
        
        vm.prank(investor1);
        greenBonds.redeemBonds();
    }
    
    // Fuzz testing for critical functions
    function testFuzzPurchaseBonds(uint256 amount) public {
        amount = bound(amount, 1, TOTAL_SUPPLY);
        
        vm.prank(investor1);
        greenBonds.purchaseBonds(amount);
        
        assertEq(greenBonds.balanceOf(investor1), amount);
        assertEq(greenBonds.availableSupply(), TOTAL_SUPPLY - amount);
    }
    
    function testFuzzCouponCalculation(uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, 1, 365 days * 10); // Up to 10 years
        
        vm.prank(investor1);
        greenBonds.purchaseBonds(100);
        
        vm.warp(block.timestamp + timeElapsed);
        
        uint256 coupon = greenBonds.calculateClaimableCoupon(investor1);
        assertTrue(coupon > 0);
        
        // Coupon should be proportional to time elapsed
        if (timeElapsed >= 365 days) {
            // Should be at least the annual coupon for 100 bonds
            uint256 expectedAnnualCoupon = 100 * FACE_VALUE * BASE_COUPON_RATE / 10000;
            assertTrue(coupon >= expectedAnnualCoupon);
        }
    }
    
    // Test invariants
    function testInvariantTotalSupply() public {
        uint256 initialSupply = greenBonds.bondTotalSupply();
        
        // Purchase some bonds
        vm.prank(investor1);
        greenBonds.purchaseBonds(500);
        
        vm.prank(investor2);
        greenBonds.purchaseBonds(300);
        
        // Total supply should remain constant
        assertEq(greenBonds.bondTotalSupply(), initialSupply);
        
        // Available supply should decrease
        assertEq(greenBonds.availableSupply(), initialSupply - 800);
        
        // Outstanding bonds should equal purchased bonds
        assertEq(greenBonds.totalSupply(), 800);
    }
    
    function testInvariantTreasuryBalance() public {
        uint256 purchaseAmount = 1000;
        uint256 cost = purchaseAmount * FACE_VALUE;
        
        uint256 contractBalanceBefore = paymentToken.balanceOf(address(greenBonds));
        
        vm.prank(investor1);
        greenBonds.purchaseBonds(purchaseAmount);
        
        uint256 contractBalanceAfter = paymentToken.balanceOf(address(greenBonds));
        
        // Contract balance should increase by the cost
        assertEq(contractBalanceAfter - contractBalanceBefore, cost);
        
        // Treasury components should sum to the cost
        (uint256 principal, uint256 coupon, uint256 project, uint256 emergency, uint256 total) = 
            greenBonds.getTreasuryStatus();
        
        assertEq(total, contractBalanceAfter);
        assertEq(principal + coupon + project + emergency, cost);
    }
    
    // Test complete lifecycle
    function testCompleteLifecycle() public {
        // 1. Purchase bonds
        uint256 bondAmount = 100;
        vm.prank(investor1);
        greenBonds.purchaseBonds(bondAmount);
        
        // 2. Add impact report
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
            1
        );
        
        // 3. Verify report (increases coupon rate)
        uint256 oldRate = greenBonds.couponRate();
        vm.prank(verifier);
        greenBonds.verifyImpactReport(0);
        assertTrue(greenBonds.couponRate() > oldRate);
        
        // 4. Claim coupon after some time
        vm.warp(block.timestamp + 180 days);
        vm.prank(investor1);
        greenBonds.claimCoupon();
        
        // 5. Redeem at maturity
        vm.warp(block.timestamp + MATURITY_PERIOD);
        vm.prank(investor1);
        greenBonds.redeemBonds();
        
        // Investor should have no bonds left
        assertEq(greenBonds.balanceOf(investor1), 0);
    }
    
    // Test multi-investor scenarios
    function testMultiInvestorScenario() public {
        // Setup multiple investors with different investment amounts
        address[5] memory investors = [
            address(0x10), address(0x11), address(0x12), address(0x13), address(0x14)
        ];
        
        uint256[5] memory amounts = [uint256(100), 200, 150, 300, 250];
        
        // Fund investors with sufficient tokens
        for (uint i = 0; i < 5; i++) {
            // Calculate required funding: bonds * face_value + buffer
            uint256 requiredFunding = amounts[i] * FACE_VALUE * 2; // 2x buffer
            
            paymentToken.transfer(investors[i], requiredFunding);
            vm.prank(investors[i]);
            paymentToken.approve(address(greenBonds), type(uint256).max);
        }
        
        // All investors purchase bonds
        uint256 totalBonds = 0;
        for (uint i = 0; i < 5; i++) {
            vm.prank(investors[i]);
            greenBonds.purchaseBonds(amounts[i]);
            
            assertEq(greenBonds.balanceOf(investors[i]), amounts[i]);
            totalBonds += amounts[i];
        }
        
        // Verify total supply
        assertEq(greenBonds.totalSupply(), totalBonds);
        assertEq(greenBonds.availableSupply(), TOTAL_SUPPLY - totalBonds);
        
        // Fast forward and claim coupons
        vm.warp(block.timestamp + 365 days);
        
        for (uint i = 0; i < 5; i++) {
            uint256 balanceBefore = paymentToken.balanceOf(investors[i]);
            
            vm.prank(investors[i]);
            greenBonds.claimCoupon();
            
            uint256 balanceAfter = paymentToken.balanceOf(investors[i]);
            assertTrue(balanceAfter > balanceBefore); // Should receive coupon
        }
        
        // Fast forward to maturity and redeem
        vm.warp(block.timestamp + MATURITY_PERIOD);
        
        for (uint i = 0; i < 5; i++) {
            vm.prank(investors[i]);
            greenBonds.redeemBonds();
            
            assertEq(greenBonds.balanceOf(investors[i]), 0);
        }
        
        // All bonds should be redeemed
        assertEq(greenBonds.totalSupply(), 0);
    }
    
    // Test governance with multiple participants
    function testGovernanceWithMultipleParticipants() public {
        // Test governance with multiple participants - ensure quorum is met
        
        address[3] memory voters = [address(0x20), address(0x21), address(0x22)];
        
        // Increase bond amounts to meet 30% quorum (3000+ votes needed)
        // Total: 1200 + 1000 + 1000 = 3200 bonds (exceeds 3000 quorum)
        uint256[3] memory bondAmounts = [uint256(1200), 1000, 1000];
        
        // Verify we have enough supply
        uint256 totalBondsNeeded = bondAmounts[0] + bondAmounts[1] + bondAmounts[2];
        uint256 availableSupply = greenBonds.availableSupply();
        
        require(totalBondsNeeded <= availableSupply, "Not enough bonds available");
        require(totalBondsNeeded >= greenBonds.quorum(), "Won't meet quorum");
        
        // Fund voters adequately
        for (uint i = 0; i < 3; i++) {
            uint256 requiredFunding = bondAmounts[i] * FACE_VALUE;
            uint256 fundingWithBuffer = requiredFunding + (requiredFunding / 2); // 1.5x
            
            paymentToken.transfer(voters[i], fundingWithBuffer);
            vm.prank(voters[i]);
            paymentToken.approve(address(greenBonds), type(uint256).max);
        }
        
        // Purchase bonds to get voting power
        for (uint i = 0; i < 3; i++) {
            vm.prank(voters[i]);
            greenBonds.purchaseBonds(bondAmounts[i]);
            
            assertEq(greenBonds.balanceOf(voters[i]), bondAmounts[i]);
        }
        
        // Create proposal
        vm.prank(issuer);
        uint256 proposalId = greenBonds.createProposal("Test Multi-Voter Proposal", address(0), "");
        
        // Cast votes with different preferences
        vm.prank(voters[0]); // 1200 votes FOR
        greenBonds.castVote(proposalId, true);
        
        vm.prank(voters[1]); // 1000 votes AGAINST
        greenBonds.castVote(proposalId, false);
        
        vm.prank(voters[2]); // 1000 votes FOR
        greenBonds.castVote(proposalId, true);
        
        // Check vote tally
        (,,,, uint256 forVotes, uint256 againstVotes,,,) = greenBonds.proposals(proposalId);
        
        // Verify vote counts
        assertEq(forVotes, 2200); // 1200 + 1000
        assertEq(againstVotes, 1000);
        
        // Verify quorum is met
        uint256 totalVotes = forVotes + againstVotes;
        uint256 quorum = greenBonds.quorum();
        assertTrue(totalVotes >= quorum, "Should meet quorum requirement");
        
        // Proposal should pass (2200 > 1000)
        assertTrue(forVotes > againstVotes, "Proposal should pass");
        
        // Execute after voting period
        vm.warp(block.timestamp + 8 days);
        
        vm.prank(voters[0]);
        greenBonds.executeProposal(proposalId);
        
        // Verify execution
        (,,,,,,,, bool executed) = greenBonds.proposals(proposalId);
        assertTrue(executed, "Proposal should be executed");
    }

    // Comprehensive governance test with proper quorum handling
    function testGovernanceWithMultipleParticipantsComprehensive() public {
        address[4] memory voters = [
            address(0x20), address(0x21), address(0x22), address(0x23)
        ];
        
        // Ensure we meet quorum: 1000 + 900 + 800 + 700 = 3400 > 3000
        uint256[4] memory bondAmounts = [uint256(1000), 900, 800, 700];
        
        // Fund and setup voters
        for (uint i = 0; i < 4; i++) {
            uint256 funding = bondAmounts[i] * FACE_VALUE * 2;
            paymentToken.transfer(voters[i], funding);
            
            vm.prank(voters[i]);
            paymentToken.approve(address(greenBonds), type(uint256).max);
            
            vm.prank(voters[i]);
            greenBonds.purchaseBonds(bondAmounts[i]);
        }
        
        // Test 1: Proposal that passes
        vm.prank(issuer);
        uint256 proposalId1 = greenBonds.createProposal("Passing Proposal", address(0), "");
        
        // FOR: 1000 + 900 = 1900, AGAINST: 800 + 700 = 1500
        vm.prank(voters[0]);
        greenBonds.castVote(proposalId1, true);
        
        vm.prank(voters[1]);
        greenBonds.castVote(proposalId1, true);
        
        vm.prank(voters[2]);
        greenBonds.castVote(proposalId1, false);
        
        vm.prank(voters[3]);
        greenBonds.castVote(proposalId1, false);
        
        vm.warp(block.timestamp + 8 days);
        vm.prank(voters[0]);
        greenBonds.executeProposal(proposalId1);
        
        (,,,,,,,, bool executed1) = greenBonds.proposals(proposalId1);
        assertTrue(executed1);
        
        // Test 2: Proposal that fails due to majority against
        vm.prank(issuer);
        uint256 proposalId2 = greenBonds.createProposal("Failing Proposal", address(0), "");
        
        // FOR: 700, AGAINST: 1000 + 900 + 800 = 2700
        vm.prank(voters[0]);
        greenBonds.castVote(proposalId2, false);
        
        vm.prank(voters[1]);
        greenBonds.castVote(proposalId2, false);
        
        vm.prank(voters[2]);
        greenBonds.castVote(proposalId2, false);
        
        vm.prank(voters[3]);
        greenBonds.castVote(proposalId2, true);
        
        vm.warp(block.timestamp + 8 days);
        
        vm.prank(voters[0]);
        vm.expectRevert(UpgradeableGreenBonds.ProposalRejected.selector);
        greenBonds.executeProposal(proposalId2);
        
        // Test 3: Quorum failure with small voters
        address smallVoter1 = address(0x30);
        address smallVoter2 = address(0x31);
        
        uint256 smallAmount = 100; // Each gets 100 bonds = 200 total << 3000 quorum
        
        for (uint i = 0; i < 2; i++) {
            address voter = i == 0 ? smallVoter1 : smallVoter2;
            paymentToken.transfer(voter, smallAmount * FACE_VALUE * 2);
            
            vm.prank(voter);
            paymentToken.approve(address(greenBonds), type(uint256).max);
            
            vm.prank(voter);
            greenBonds.purchaseBonds(smallAmount);
        }
        
        vm.prank(issuer);
        uint256 proposalId3 = greenBonds.createProposal("Low Participation", address(0), "");
        
        // Only small voters vote (200 total votes << 3000 quorum)
        vm.prank(smallVoter1);
        greenBonds.castVote(proposalId3, true);
        
        vm.prank(smallVoter2);
        greenBonds.castVote(proposalId3, true);
        
        vm.warp(block.timestamp + 8 days);
        
        vm.prank(smallVoter1);
        vm.expectRevert(UpgradeableGreenBonds.QuorumNotReached.selector);
        greenBonds.executeProposal(proposalId3);
        
        // Test 4: Voting restrictions
        vm.prank(issuer);
        uint256 proposalId4 = greenBonds.createProposal("Restriction Test", address(0), "");
        
        // Double voting
        vm.prank(voters[0]);
        greenBonds.castVote(proposalId4, true);
        
        vm.prank(voters[0]);
        vm.expectRevert(UpgradeableGreenBonds.AlreadyVoted.selector);
        greenBonds.castVote(proposalId4, false);
        
        // No voting power
        address nonVoter = address(0x99);
        vm.prank(nonVoter);
        vm.expectRevert(UpgradeableGreenBonds.NoVotingPower.selector);
        greenBonds.castVote(proposalId4, true);
    }
    
    // Test tranche lifecycle
    function testTrancheLifecycle() public {
        // Add multiple tranches
        vm.prank(issuer);
        greenBonds.addTranche("Senior", 1500 * 10**18, 300, 1, 1000);
        
        vm.prank(issuer);
        greenBonds.addTranche("Subordinate", 800 * 10**18, 700, 2, 2000);
        
        // Purchase from different tranches
        vm.prank(investor1);
        greenBonds.purchaseTrancheBonds(0, 50); // Senior
        
        vm.prank(investor2);
        greenBonds.purchaseTrancheBonds(1, 100); // Subordinate
        
        // Test coupon calculations
        vm.warp(block.timestamp + 365 days);
        
        uint256 seniorCoupon = greenBonds.calculateTrancheCoupon(0, investor1);
        uint256 subCoupon = greenBonds.calculateTrancheCoupon(1, investor2);
        
        assertTrue(seniorCoupon > 0);
        assertTrue(subCoupon > 0);
        
        // Subordinate should have higher coupon rate
        assertTrue(subCoupon > seniorCoupon);
        
        // Claim coupons
        vm.prank(investor1);
        greenBonds.claimTrancheCoupon(0);
        
        vm.prank(investor2);
        greenBonds.claimTrancheCoupon(1);
        
        // Transfer tranche bonds
        vm.prank(investor1);
        greenBonds.transferTrancheBonds(0, investor2, 25);
        
        assertEq(greenBonds.getTrancheHoldings(0, investor1), 25);
        assertEq(greenBonds.getTrancheHoldings(0, investor2), 25);
        
        // Redeem at maturity
        vm.warp(block.timestamp + MATURITY_PERIOD);
        
        vm.prank(investor1);
        greenBonds.redeemTrancheBonds(0);
        
        vm.prank(investor2);
        greenBonds.redeemTrancheBonds(0);
        
        vm.prank(investor2);
        greenBonds.redeemTrancheBonds(1);
    }
    
    // Test error recovery scenarios
    function testErrorRecoveryScenarios() public {
        // Test recovery after failed operations
        vm.prank(investor1);
        greenBonds.purchaseBonds(100);
        
        // Try to claim coupon too early
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.NoCouponAvailable.selector);
        greenBonds.claimCoupon();
        
        // Wait and try again - should work
        vm.warp(block.timestamp + 30 days);
        vm.prank(investor1);
        greenBonds.claimCoupon();
        
        // Test redemption recovery
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.BondNotMatured.selector);
        greenBonds.redeemBonds();
        
        // Wait until maturity
        vm.warp(block.timestamp + MATURITY_PERIOD);
        vm.prank(investor1);
        greenBonds.redeemBonds();
    }
    
    // Test upgrade authorization
    function testUpgradeAuthorization() public {
        // Test that upgrade role exists and is properly set
        assertTrue(greenBonds.hasRole(greenBonds.UPGRADER_ROLE(), upgrader));
        assertFalse(greenBonds.hasRole(greenBonds.UPGRADER_ROLE(), investor1));
        
        // Test adding/removing upgrade role
        vm.prank(admin);
        greenBonds.grantRole(greenBonds.UPGRADER_ROLE(), investor1);
        assertTrue(greenBonds.hasRole(greenBonds.UPGRADER_ROLE(), investor1));
        
        vm.prank(admin);
        greenBonds.revokeRole(greenBonds.UPGRADER_ROLE(), investor1);
        assertFalse(greenBonds.hasRole(greenBonds.UPGRADER_ROLE(), investor1));
        
        // Test that state is preserved 
        assertEq(greenBonds.bondName(), BOND_NAME);
        assertEq(greenBonds.faceValue(), FACE_VALUE);
        assertEq(greenBonds.version(), "v1.0.0");
    }
    
    // Test fund allocation edge cases
    function testFundAllocationEdgeCases() public {
        // Test with very small purchase
        vm.prank(investor1);
        greenBonds.purchaseBonds(1);
        
        (uint256 principal, uint256 coupon, uint256 project, uint256 emergency, uint256 total) = 
            greenBonds.getTreasuryStatus();
        
        // All allocations should be non-zero
        assertTrue(principal > 0);
        assertTrue(coupon > 0);
        assertTrue(project > 0);
        assertTrue(emergency > 0);
        assertTrue(total > 0);
        
        // Test allocation percentage updates
        vm.prank(admin);
        greenBonds.updateAllocationPercentages(6000, 3000, 1000); // 60%, 30%, 10%
        
        // New purchase should use new allocations
        vm.prank(investor2);
        greenBonds.purchaseBonds(1);
    }
    
    // Test time-based operations
    function testTimeBasedOperations() public {
        uint256 baseTime = block.timestamp;
        
        // Purchase at different times
        vm.prank(investor1);
        greenBonds.purchaseBonds(50);
        
        vm.warp(baseTime + 30 days);
        vm.prank(investor2);
        greenBonds.purchaseBonds(50);
        
        // Fast forward and check coupon calculations
        vm.warp(baseTime + 365 days);
        
        uint256 coupon1 = greenBonds.calculateClaimableCoupon(investor1);
        uint256 coupon2 = greenBonds.calculateClaimableCoupon(investor2);
        
        // investor1 should have more coupon (held bonds longer)
        assertTrue(coupon1 > coupon2);
        
        // Test maturity detection
        vm.warp(baseTime + MATURITY_PERIOD + 1);
        assertTrue(block.timestamp >= greenBonds.maturityDate());
    }
    
    // Test emergency scenarios
    function testEmergencyScenarios() public {
        // Test emergency pause
        vm.prank(investor1);
        greenBonds.purchaseBonds(100);
        
        vm.prank(admin);
        greenBonds.pause();
        
        // Operations should fail when paused with EnforcedPause() error
        vm.prank(investor1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        greenBonds.claimCoupon();
        
        vm.prank(investor2);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        greenBonds.purchaseBonds(10);
        
        // Test other paused operations
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        greenBonds.addTranche("Test", 1000, 100, 1, 100);
        
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        greenBonds.updateCouponPeriod(45 days);
        
        string[] memory metricNames = new string[](1);
        metricNames[0] = "test_metric";
        uint256[] memory metricValues = new uint256[](1);
        metricValues[0] = 100;
        
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        greenBonds.addImpactReport(
            "test_uri", 
            "test_hash", 
            "{}", 
            metricNames, 
            metricValues, 
            7 days, 
            1
        );
        
        vm.prank(treasurer);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        greenBonds.withdrawProjectFunds(treasurer, 1000, "test");
        
        // Emergency recovery should work even when paused (no whenNotPaused modifier)
        paymentToken.transfer(address(greenBonds), 1000 * 10**18);
        
        vm.prank(admin);
        greenBonds.emergencyRecovery(admin, 500 * 10**18);
        
        // Fast forward past timelock
        vm.warp(block.timestamp + 3 days);
        
        vm.prank(admin);
        greenBonds.emergencyRecovery(admin, 500 * 10**18);
        
        // Unpause and resume operations
        vm.prank(admin);
        greenBonds.unpause();
        
        // Operations should work after unpause
        vm.prank(investor1);
        greenBonds.claimCoupon();
        
        vm.prank(investor2);
        greenBonds.purchaseBonds(5);
        assertEq(greenBonds.balanceOf(investor2), 5);
    }
    
    // Test boundary conditions
    function testBoundaryConditions() public {
        // Test at maximum supply
        vm.prank(investor1);
        greenBonds.purchaseBonds(TOTAL_SUPPLY);
        
        assertEq(greenBonds.availableSupply(), 0);
        
        // No more bonds should be available
        vm.prank(investor2);
        vm.expectRevert(UpgradeableGreenBonds.InsufficientBondsAvailable.selector);
        greenBonds.purchaseBonds(1);
        
        // Test at maturity boundary
        vm.warp(greenBonds.maturityDate() - 1);
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.BondNotMatured.selector);
        greenBonds.redeemBonds();
        
        // Exactly at maturity should work
        vm.warp(greenBonds.maturityDate());
        vm.prank(investor1);
        greenBonds.redeemBonds();
    }

    // Test all timelock functions systematically
    function testTimelockSystemComprehensive() public {
        // Test updateGovernanceParams timelock
        vm.prank(admin);
        greenBonds.updateGovernanceParams(2000, 5 days);
        
        // Should remain unchanged (scheduled)
        (uint256 quorum,,) = greenBonds.getGovernanceParams();
        assertEq(quorum, 3000); // Original value
        
        // Fast forward and execute
        vm.warp(block.timestamp + 3 days);
        vm.prank(admin);
        greenBonds.updateGovernanceParams(2000, 5 days);
        
        (quorum,,) = greenBonds.getGovernanceParams();
        assertEq(quorum, 2000); // Updated value
        
        // Test issuerEmergencyWithdraw timelock
        vm.prank(investor1);
        greenBonds.purchaseBonds(100);
        
        // Get initial balances before scheduling emergency withdrawal
        uint256 issuerBalanceBefore = paymentToken.balanceOf(issuer);
        (,,, uint256 emergencyReserveBefore,) = greenBonds.getTreasuryStatus();
        
        // Should not withdraw immediately (scheduled only)
        vm.prank(issuer);
        greenBonds.issuerEmergencyWithdraw(1000);
        
        // Verify funds were NOT withdrawn (operation only scheduled)
        uint256 issuerBalanceAfterSchedule = paymentToken.balanceOf(issuer);
        (,,, uint256 emergencyReserveAfterSchedule,) = greenBonds.getTreasuryStatus();
        
        // Assert balances unchanged (proves scheduling worked, execution didn't happen)
        assertEq(issuerBalanceAfterSchedule, issuerBalanceBefore, "Issuer balance should be unchanged after scheduling");
        assertEq(emergencyReserveAfterSchedule, emergencyReserveBefore, "Emergency reserve should be unchanged after scheduling");
        
        // Fast forward past timelock period
        vm.warp(block.timestamp + 3 days);
        
        // Now execute the scheduled withdrawal
        vm.prank(issuer);
        greenBonds.issuerEmergencyWithdraw(1000);
        
        // Verify funds were actually withdrawn (execution worked)
        uint256 issuerBalanceAfterExecution = paymentToken.balanceOf(issuer);
        (,,, uint256 emergencyReserveAfterExecution,) = greenBonds.getTreasuryStatus();
        
        // Assert withdrawal actually happened
        assertTrue(issuerBalanceAfterExecution > issuerBalanceBefore, "Issuer should receive tokens after execution");
        assertTrue(emergencyReserveAfterExecution < emergencyReserveBefore, "Emergency reserve should decrease after execution");
        
        // Verify exact amounts (if withdrawal was successful)
        uint256 actualWithdrawn = issuerBalanceAfterExecution - issuerBalanceBefore;
        uint256 reserveDecrease = emergencyReserveBefore - emergencyReserveAfterExecution;
        
        // The withdrawn amount should match the reserve decrease (may be less than 1000 if insufficient funds)
        assertEq(actualWithdrawn, reserveDecrease, "Withdrawn amount should match reserve decrease");
        assertTrue(actualWithdrawn <= 1000, "Cannot withdraw more than requested");
    }

    // Test that different operations create different IDs
    function testTimelockOperationIdGeneration() public {
        // These should create different operation IDs
        vm.prank(issuer);
        greenBonds.updateCouponPeriod(60 days);
        
        vm.prank(issuer);
        greenBonds.updateCouponPeriod(90 days); // Different parameter
        
        // Both should be scheduled (not executed)
        assertEq(greenBonds.couponPeriod(), 30 days); // Original value
        
        // Execute both after timelock
        vm.warp(block.timestamp + 3 days);
        
        vm.prank(issuer);
        greenBonds.updateCouponPeriod(60 days);
        assertEq(greenBonds.couponPeriod(), 60 days);
        
        vm.prank(issuer);
        greenBonds.updateCouponPeriod(90 days);
        assertEq(greenBonds.couponPeriod(), 90 days);
    }

    // Test actual execution of governance proposals that modify state
    function testGovernanceProposalExecution() public {
        vm.prank(admin);
        greenBonds.grantRole(greenBonds.ISSUER_ROLE(), address(greenBonds));
        
        // Test 1: Proposal to add green certification
        bytes memory callData1 = abi.encodeWithSelector(
            greenBonds.addGreenCertification.selector,
            "BREEAM Excellent"
        );
        
        vm.prank(issuer);
        uint256 proposalId1 = greenBonds.createProposal("Add BREEAM cert", address(greenBonds), callData1);
        
        // Vote and execute
        vm.prank(investor1);
        greenBonds.purchaseBonds(3500);
        
        vm.prank(investor1);
        greenBonds.castVote(proposalId1, true);
        
        vm.warp(block.timestamp + 8 days);
        vm.prank(investor1);
        greenBonds.executeProposal(proposalId1);
        
        assertEq(greenBonds.getGreenCertificationCount(), 1);
        
        // Test 2: Proposal to update allocation percentages
        vm.prank(admin);
        greenBonds.grantRole(greenBonds.DEFAULT_ADMIN_ROLE(), address(greenBonds));
        
        bytes memory callData2 = abi.encodeWithSelector(
            greenBonds.updateAllocationPercentages.selector,
            4000, 5500, 500
        );
        
        vm.prank(issuer);
        uint256 proposalId2 = greenBonds.createProposal("Update allocations", address(greenBonds), callData2);
        
        vm.prank(investor1);
        greenBonds.castVote(proposalId2, true);
        
        vm.warp(block.timestamp + 8 days);
        vm.prank(investor1);
        greenBonds.executeProposal(proposalId2);
        
        (uint256 principal, uint256 project, uint256 emergency) = greenBonds.getAllocationPercentages();
        assertEq(principal, 4000);
        assertEq(project, 5500);
        assertEq(emergency, 500);
    }

    // Test voting power changes during voting period
    function testGovernanceVotingPowerChanges() public {
        vm.prank(issuer);
        uint256 proposalId = greenBonds.createProposal("Test", address(0), "");
        
        // Initial voting power
        vm.prank(investor1);
        greenBonds.purchaseBonds(1000);
        
        vm.prank(investor1);
        greenBonds.castVote(proposalId, true);
        
        // Buy more bonds after voting (shouldn't affect current vote)
        vm.prank(investor1);
        greenBonds.purchaseBonds(2000);
        
        // Check vote is recorded with original power
        (,,,, uint256 forVotes, uint256 againstVotes,,,) = greenBonds.proposals(proposalId);
        assertEq(forVotes, 1000); // Not 3000
        assertEq(againstVotes, 0);
        
        // Transfer bonds to another voter
        vm.prank(investor1);
        greenBonds.transfer(investor2, 500);
        
        // investor2 can vote with transferred bonds
        vm.prank(investor2);
        greenBonds.castVote(proposalId, false);
        
        (,,,, forVotes, againstVotes,,,) = greenBonds.proposals(proposalId);
        assertEq(forVotes, 1000);
        assertEq(againstVotes, 500);
    }

    // Add multiple tranches with different characteristics
    function testTrancheInteractionEdgeCases() public {
        vm.prank(issuer);
        greenBonds.addTranche("AAA Senior", 2000 * 10**18, 300, 1, 500);
        
        vm.prank(issuer);
        greenBonds.addTranche("BBB Mezzanine", 1500 * 10**18, 600, 2, 800);
        
        vm.prank(issuer);
        greenBonds.addTranche("CCC Junior", 1000 * 10**18, 1000, 3, 1200);
        
        // Test purchasing from non-existent tranche
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.TrancheDoesNotExist.selector);
        greenBonds.purchaseTrancheBonds(10, 100);
        
        // Test transfers with zero amounts
        vm.prank(investor1);
        greenBonds.purchaseTrancheBonds(0, 50);
        
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.InvalidValue.selector);
        greenBonds.transferTrancheBonds(0, investor2, 0);
        
        // Test transferring more than owned
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.InsufficientBonds.selector);
        greenBonds.transferTrancheBonds(0, investor2, 100);
        
        // Test self-transfer
        vm.prank(investor1);
        greenBonds.transferTrancheBonds(0, investor1, 25);
        assertEq(greenBonds.getTrancheHoldings(0, investor1), 50);
    }

    // Test add tranche and maturity redemption
    function testTrancheMaturityAndRedemption() public {
        // Add tranches
        vm.prank(issuer);
        greenBonds.addTranche("Senior", 1500 * 10**18, 400, 1, 1000);
        
        // Purchase tranche bonds
        vm.prank(investor1);
        greenBonds.purchaseTrancheBonds(0, 100);
        
        // Test early redemption attempt
        vm.prank(investor1);
        vm.expectRevert(UpgradeableGreenBonds.BondNotMatured.selector);
        greenBonds.redeemTrancheBonds(0);
        
        // Test redemption at maturity
        vm.warp(block.timestamp + MATURITY_PERIOD + 1);
        
        uint256 balanceBefore = paymentToken.balanceOf(investor1);
        
        vm.prank(investor1);
        greenBonds.redeemTrancheBonds(0);
        
        uint256 balanceAfter = paymentToken.balanceOf(investor1);
        assertTrue(balanceAfter > balanceBefore);
        assertEq(greenBonds.getTrancheHoldings(0, investor1), 0);
    }

    // Test coupon calculation with very small amounts and time periods
    function testCouponCalculationPrecision() public {
        vm.prank(investor1);
        greenBonds.purchaseBonds(1); // Single bond
        
        // Test 1 second coupon
        vm.warp(block.timestamp + 1);
        uint256 coupon1s = greenBonds.calculateClaimableCoupon(investor1);
        assertTrue(coupon1s > 0);
        
        // Test 1 minute coupon
        vm.warp(block.timestamp + 59); // Total 60 seconds
        uint256 coupon1m = greenBonds.calculateClaimableCoupon(investor1);
        assertEq(coupon1m, coupon1s * 60);
        
        // Test leap year calculations (366 days)
        vm.warp(block.timestamp + 366 days - 60);
        uint256 couponLeapYear = greenBonds.calculateClaimableCoupon(investor1);
        
        // Should be slightly more than regular year
        vm.warp(block.timestamp - 1 days);
        uint256 couponRegularYear = greenBonds.calculateClaimableCoupon(investor1);
        assertTrue(couponLeapYear > couponRegularYear);
    }

    // Test coupon calculations when rates change mid-period
    function testCouponRateChanges() public {
        vm.prank(investor1);
        greenBonds.purchaseBonds(100);
        
        vm.warp(block.timestamp + 100 days);
        
        // Add and verify impact report to increase coupon rate
        string[] memory metricNames = new string[](1);
        metricNames[0] = "co2_reduction";
        uint256[] memory metricValues = new uint256[](1);
        metricValues[0] = 1000;
        
        vm.prank(issuer);
        greenBonds.addImpactReport("uri", "hash", "{}", metricNames, metricValues, 7 days, 1);
        
        uint256 rateBefore = greenBonds.couponRate();
        
        vm.prank(verifier);
        greenBonds.verifyImpactReport(0);
        
        uint256 rateAfter = greenBonds.couponRate();
        assertTrue(rateAfter > rateBefore);
        
        // Wait additional time with new rate
        vm.warp(block.timestamp + 100 days);
        
        uint256 finalCoupon = greenBonds.calculateClaimableCoupon(investor1);
        assertTrue(finalCoupon > 0);
        
        // Claim coupon
        vm.prank(investor1);
        greenBonds.claimCoupon();
        
        // Verify calculation starts fresh with new rate
        vm.warp(block.timestamp + 100 days);
        uint256 newPeriodCoupon = greenBonds.calculateClaimableCoupon(investor1);
        
        // Should be calculated with higher rate
        assertTrue(newPeriodCoupon > 0);
    }

    // Test complete impact reporting workflow
    function testImpactReportingWorkflow() public {
        string[] memory metricNames = new string[](3);
        metricNames[0] = "co2_reduction_tons";
        metricNames[1] = "energy_generated_mwh";
        metricNames[2] = "trees_planted";
        
        uint256[] memory metricValues = new uint256[](3);
        metricValues[0] = 1500;
        metricValues[1] = 2500;
        metricValues[2] = 1000;
        
        // Add multiple verifiers
        vm.prank(admin);
        greenBonds.addVerifier(address(0x20));
        vm.prank(admin);
        greenBonds.addVerifier(address(0x21));
        
        // Add report requiring multiple verifications
        vm.prank(issuer);
        greenBonds.addImpactReport(
            "https://reports.example.com/2024-q1",
            "0xabcd1234",
            '{"co2": 1500, "energy": 2500, "trees": 1000}',
            metricNames,
            metricValues,
            14 days,
            3 // Require 3 verifications
        );
        
        // Partial verification
        vm.prank(verifier);
        greenBonds.verifyImpactReport(0);
        
        vm.prank(address(0x20));
        greenBonds.verifyImpactReport(0);
        
        // Not finalized yet
        uint256 rateBefore = greenBonds.couponRate();
        
        // Final verification
        vm.prank(address(0x21));
        greenBonds.verifyImpactReport(0);
        
        // Should be finalized and rate increased
        uint256 rateAfter = greenBonds.couponRate();
        assertTrue(rateAfter > rateBefore);
        
        // Verify all metrics are stored correctly
        assertEq(greenBonds.getImpactMetricValue(0, "co2_reduction_tons"), 1500);
        assertEq(greenBonds.getImpactMetricValue(0, "energy_generated_mwh"), 2500);
        assertEq(greenBonds.getImpactMetricValue(0, "trees_planted"), 1000);
    }

    // Test challenging and recovering from challenged reports
    function testImpactReportChallengingAndRecovery() public {
        string[] memory metricNames = new string[](1);
        metricNames[0] = "co2_reduction";
        uint256[] memory metricValues = new uint256[](1);
        metricValues[0] = 1000;
        
        vm.prank(admin);
        greenBonds.addVerifier(address(0x30));
        vm.prank(admin);
        greenBonds.addVerifier(address(0x31));
        
        vm.prank(issuer);
        greenBonds.addImpactReport("uri", "hash", "{}", metricNames, metricValues, 7 days, 2);
        
        // First verification
        vm.prank(verifier);
        greenBonds.verifyImpactReport(0);
        
        // Challenge before second verification
        vm.prank(address(0x30));
        greenBonds.challengeImpactReport(0, "Questionable measurements");
        
        // Verification should be reset
        address[] memory verifiers = greenBonds.getReportVerifiers(0);
        assertEq(verifiers.length, 0);
        
        // Re-verify after challenge
        vm.prank(verifier);
        greenBonds.verifyImpactReport(0);
        
        vm.prank(address(0x31));
        greenBonds.verifyImpactReport(0);
        
        // Should now be finalized
        verifiers = greenBonds.getReportVerifiers(0);
        assertEq(verifiers.length, 2);
    }

    // Test treasury accounting under various scenarios
    function testTreasuryIntegrity() public {
        // Large purchase
        vm.prank(investor1);
        greenBonds.purchaseBonds(1000);
        
        (, uint256 c1 ,,, uint256 t1) = greenBonds.getTreasuryStatus();
        
        // Large coupon claim
        vm.warp(block.timestamp + 365 days);
        vm.prank(investor1);
        greenBonds.claimCoupon();
        
        (, uint256 c2, uint256 pr2, , uint256 t2) = greenBonds.getTreasuryStatus();
        
        // Coupon reserve should decrease
        assertTrue(c2 < c1);
        assertTrue(t2 < t1);
        
        // Project fund withdrawal
        uint256 withdrawAmount = pr2 / 3;
        vm.prank(treasurer);
        greenBonds.withdrawProjectFunds(treasurer, withdrawAmount, "Equipment purchase");
        
        (uint256 p3, uint256 c3, uint256 pr3, uint256 e3, uint256 t3) = greenBonds.getTreasuryStatus();
        
        // Project funds should decrease
        assertEq(pr3, pr2 - withdrawAmount);
        assertEq(t3, t2 - withdrawAmount);
        
        // Verify total integrity
        assertEq(p3 + c3 + pr3 + e3, t3);
    }

    // Test various early redemption scenarios
    function testEarlyRedemptionScenarios() public {
        vm.prank(issuer);
        greenBonds.setEarlyRedemptionParams(true, 500); // 5% penalty
        
        // Test partial early redemption
        vm.prank(investor1);
        greenBonds.purchaseBonds(100);
        
        vm.prank(investor1);
        greenBonds.redeemBondsEarly(50);
        
        assertEq(greenBonds.balanceOf(investor1), 50);
        
        // Test penalty rate changes
        vm.prank(issuer);
        greenBonds.setEarlyRedemptionParams(true, 300); // Reduce to 3%
        
        uint256 balanceBefore = paymentToken.balanceOf(investor1);
        
        vm.prank(investor1);
        greenBonds.redeemBondsEarly(50); // Remaining bonds
        
        uint256 balanceAfter = paymentToken.balanceOf(investor1);
        
        // Should receive more due to lower penalty
        uint256 expectedValue = 50 * FACE_VALUE;
        uint256 expectedPenalty = expectedValue * 300 / 10000;
        uint256 expectedPayout = expectedValue - expectedPenalty;
        
        assertEq(balanceAfter - balanceBefore, expectedPayout);
    }

