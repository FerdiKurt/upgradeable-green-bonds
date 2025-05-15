// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Upgradeable GreenBonds
/// @notice A comprehensive smart contract implementing a green bond to support climate and environmental projects
/// @dev Uses AccessControl for role-based permissions
contract UpgradeableGreenBonds is 
    Initializable, 
    AccessControlUpgradeable, 
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ERC20Upgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice Custom errors 
    error BondMatured();
    error BondNotMatured();
    error InsufficientBondsAvailable();
    error InvalidBondAmount();
    error NoCouponAvailable();
    error NoBondsToRedeem();
    error PaymentFailed();
    error ReportDoesNotExist();
    error ReportAlreadyVerified();
    error TooEarlyForWithdrawal();
    error InsufficientFunds();
    error EarlyRedemptionNotEnabled();
    error InsufficientBonds();
    error ProposalDoesNotExist();
    error VotingPeriodEnded();
    error ProposalAlreadyExecuted();
    error QuorumNotReached();
    error TrancheDoesNotExist();
    error OperationNotScheduled();
    error TimelockNotExpired();
    error FailedExecution();
    error ChallengePeriodEnded();
    error AlreadyVoted();

    /// @notice Role definitions
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    /// @notice Precision factor for calculations
    uint256 private constant PRECISION_FACTOR = 1e18;
    
    /// @notice Bond details
    /// @dev Core financial parameters of the bond
    string public bondName;
    string public bondSymbol;
    uint256 public faceValue;
    uint256 public bondTotalSupply;  // Renamed from totalSupply to avoid conflict with ERC20
    uint256 public availableSupply;
    uint256 public baseCouponRate; // Base rate in basis points (e.g., 500 = 5.00%)
    uint256 public greenPremiumRate; // Additional rate based on green performance
    uint256 public maxCouponRate; // Cap on total rate
    uint256 public couponRate; // Current effective rate (base + green premium)
    uint256 public couponPeriod; // in seconds
    uint256 public maturityDate;
    uint256 public issuanceDate;
    
    // Payment token (e.g., USDC, DAI)
    IERC20 public paymentToken;
    
    // Treasury system
    struct Treasury {
        uint256 principalReserve;  // For bond redemption
        uint256 couponReserve;     // For coupon payments
        uint256 projectFunds;      // For green project implementation
        uint256 emergencyReserve;  // For unexpected expenses
    }
    Treasury public treasury;
    
    // Early redemption parameters
    uint256 public earlyRedemptionPenaltyBps; // Penalty in basis points
    bool public earlyRedemptionEnabled;
    
    // Green project details
    string public projectDescription;
    string public impactMetrics;
    string[] public greenCertifications;
    
    // Impact reports
    struct EnhancedImpactReport {
        string reportURI;
        string reportHash;
        uint256 timestamp;
        string impactMetricsJson; // JSON string of metrics
        uint256 challengePeriodEnd;
        uint256 verificationCount;
        uint256 requiredVerifications;
        bool finalized;
        mapping(address => bool) hasVerified;
        mapping(string => uint256) quantitativeMetrics; // Name -> value mapping
        string[] metricNames;
    }
    
    // Impact reports storage
    mapping(uint256 => EnhancedImpactReport) public impactReports;
    uint256 public impactReportCount;
    
    // Tranches for different bond classes
    struct Tranche {
        string name;
        uint256 faceValue;
        uint256 couponRate;
        uint256 seniority; // Lower number = more senior
        uint256 totalSupply;
        uint256 availableSupply;
        mapping(address => uint256) holdings;
        mapping(address => uint256) lastCouponClaimDate;
    }
    
    // Tranche storage
    mapping(uint256 => Tranche) public tranches;
    uint256 public trancheCount;
    
    // Governance parameters
    struct Proposal {
        address proposer;
        string description;
        bytes callData;
        address target;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        mapping(address => bool) hasVoted;
    }
    
    // Governance storage
    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;
    uint256 public quorum;
    uint256 public votingPeriod;
    
    // Timelock for critical operations
    mapping(bytes32 => uint256) public operationTimestamps;
    uint256 public constant TIMELOCK_PERIOD = 2 days;
    
    // Dashboard contract reference
    address public dashboardContract;
    
    // Coupon claim tracking for standard bonds
    mapping(address => uint256) public lastCouponClaimDate;
    
    // Events
    event BondPurchased(address indexed investor, uint256 amount, uint256 tokensSpent);
    event CouponClaimed(address indexed investor, uint256 amount);
    event BondRedeemed(address indexed investor, uint256 amount, uint256 tokensReceived);
    event ImpactReportAdded(uint256 indexed reportId, string reportURI);
    event ImpactReportVerified(uint256 indexed reportId, address verifier);
    event ImpactReportFinalized(uint256 indexed reportId);
    event ImpactReportChallenged(uint256 indexed reportId, address challenger, string reason);
    event FundsAllocated(string projectComponent, uint256 amount);
    event CouponRateUpdated(uint256 newRate);
    event EarlyRedemptionStatusChanged(bool enabled);
    event BondRedeemedEarly(address indexed investor, uint256 amount, uint256 tokensReceived, uint256 penalty);
    event BondParametersUpdated(
        uint256 oldCouponRate,
        uint256 newCouponRate,
        uint256 oldCouponPeriod,
        uint256 newCouponPeriod
    );
    event ImpactMetricsAchieved(
        uint256 reportId,
        string[] metrics,
        uint256[] values,
        uint256 timestamp
    );
    event FundWithdrawal(
        address indexed recipient,
        uint256 amount,
        string purpose,
        uint256 timestamp
    );
    event DashboardContractUpdated(address newDashboard);
    event ProposalCreated(uint256 indexed proposalId, address proposer, string description);
    event VoteCast(address indexed voter, uint256 indexed proposalId, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event OperationScheduled(bytes32 indexed operationId, uint256 executionTime);
    event TrancheAdded(uint256 indexed trancheId, string name, uint256 couponRate, uint256 seniority);
    event TrancheBondPurchased(address indexed investor, uint256 indexed trancheId, uint256 amount, uint256 tokensSpent);
    event TrancheCouponClaimed(address indexed investor, uint256 indexed trancheId, uint256 amount);
    event TrancheBondRedeemed(address indexed investor, uint256 indexed trancheId, uint256 amount, uint256 tokensReceived);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /// @notice Initialize the green bond (replaces constructor for upgradeable contract)
    /// @param _name Name of the bond
    /// @param _symbol Bond symbol identifier
    /// @param _faceValue Face value of each bond unit
    /// @param _totalSupply Total number of bonds issued
    /// @param _baseCouponRate Annual base interest rate in basis points (e.g., 500 = 5.00%)
    /// @param _maxCouponRate Maximum possible coupon rate in basis points
    /// @param _couponPeriod Time between coupon payments in seconds
    /// @param _maturityPeriod Time until bond matures in seconds
    /// @param _paymentTokenAddress Address of ERC20 token used for payments
    /// @param _projectDescription Description of the green project
    /// @param _impactMetrics Description of environmental impact metrics tracked
    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 _faceValue,
        uint256 _totalSupply,
        uint256 _baseCouponRate,
        uint256 _maxCouponRate,
        uint256 _couponPeriod,
        uint256 _maturityPeriod,
        address _paymentTokenAddress,
        string memory _projectDescription,
        string memory _impactMetrics
    ) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __ERC20_init(_name, _symbol);
        __UUPSUpgradeable_init();
        
        bondName = _name;
        bondSymbol = _symbol;
        faceValue = _faceValue;
        bondTotalSupply = _totalSupply;
        availableSupply = _totalSupply;
        baseCouponRate = _baseCouponRate;
        maxCouponRate = _maxCouponRate;
        couponRate = _baseCouponRate; // Initially set to base rate
        couponPeriod = _couponPeriod;
        issuanceDate = block.timestamp;
        maturityDate = block.timestamp + _maturityPeriod;
        paymentToken = IERC20(_paymentTokenAddress);
        projectDescription = _projectDescription;
        impactMetrics = _impactMetrics;
        
        // Initialize governance parameters
        quorum = _totalSupply * 30 / 100; // 30% quorum
        votingPeriod = 7 days;
        
        // Initialize early redemption parameters
        earlyRedemptionPenaltyBps = 300; // 3% penalty
        earlyRedemptionEnabled = false;
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ISSUER_ROLE, msg.sender);
        _grantRole(TREASURY_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }
    
    /// @notice Authorizes contract upgrades via UUPS pattern
    /// @param newImplementation Address of the new contract implementation
    /// @dev Restricts upgrades to accounts with UPGRADER_ROLE
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {
        // No additional validation needed beyond the role check
    }
    
    /// @notice Circuit breaker - pauses the contract
    /// @dev Only callable by admin
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    /// @notice Unpause the contract
    /// @dev Only callable by admin
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
    
    /// @notice Schedule an operation for timelock
    /// @param operationId Unique identifier for the operation
    /// @dev Internal function to create timelocks for sensitive operations
    function scheduleOperation(bytes32 operationId) internal {
        operationTimestamps[operationId] = block.timestamp + TIMELOCK_PERIOD;
        emit OperationScheduled(operationId, block.timestamp + TIMELOCK_PERIOD);
    }
    
    /// @notice Add a verifier who can validate impact reports
    /// @param verifier Address to be granted verifier role
    /// @dev Only callable by admin
    function addVerifier(address verifier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(VERIFIER_ROLE, verifier);
    }
    
    /// @notice Add a treasurer who can manage funds
    /// @param treasurer Address to be granted treasurer role
    /// @dev Only callable by admin
    function addTreasurer(address treasurer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(TREASURY_ROLE, treasurer);
    }
    
    /// @notice Add an upgrader who can upgrade the contract
    /// @param upgrader Address to be granted upgrader role
    /// @dev Only callable by admin
    function addUpgrader(address upgrader) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(UPGRADER_ROLE, upgrader);
    }
    
    /// @notice Add a green certification
    /// @param certification String describing the certification (e.g., "LEED Gold")
    /// @dev Only callable by issuer
    function addGreenCertification(string memory certification) external onlyRole(ISSUER_ROLE) whenNotPaused {
        greenCertifications.push(certification);
    }
    
    /// @notice Purchase bonds with payment tokens
    /// @param bondAmount The number of bonds to purchase
    /// @dev Transfers payment tokens from buyer to contract and mints ERC20 tokens
    function purchaseBonds(uint256 bondAmount) external nonReentrant whenNotPaused {
        if (block.timestamp >= maturityDate) revert BondMatured();
        if (bondAmount == 0) revert InvalidBondAmount();
        if (bondAmount > availableSupply) revert InsufficientBondsAvailable();
        
        // Calculate cost safely
        uint256 cost = bondAmount * faceValue;
        
        // Transfer payment tokens from buyer to contract
        paymentToken.safeTransferFrom(msg.sender, address(this), cost);
        
        // Mint ERC20 tokens representing bond ownership
        _mint(msg.sender, bondAmount);
        
        // Allocate funds to different reserves - safely breaking down calculations
        uint256 timeToMaturity = 0;
        if (maturityDate > block.timestamp) {
            timeToMaturity = maturityDate - block.timestamp;
        }
        
        uint256 couponAllocation = 0;
        if (timeToMaturity > 0) {
            // Calculate annual coupon
            uint256 annualCouponPercentage = couponRate;
            uint256 annualCouponAmount = cost * annualCouponPercentage / 10000;
            
            // Calculate time-proportional coupon allocation
            uint256 secondsPerYear = 365 days;
            couponAllocation = (annualCouponAmount * timeToMaturity) / secondsPerYear;
        }
        
        // Update treasury balances
        treasury.principalReserve += cost;
        treasury.couponReserve += couponAllocation;
        
        uint256 remainingAmount = cost - couponAllocation;
        uint256 projectAllocation = (remainingAmount * 90) / 100;  // 90% for project
        uint256 emergencyAllocation = remainingAmount - projectAllocation; // Remainder for emergency
        
        treasury.projectFunds += projectAllocation;
        treasury.emergencyReserve += emergencyAllocation;
        
        // Update bond state
        availableSupply = availableSupply - bondAmount;
        lastCouponClaimDate[msg.sender] = block.timestamp;
        
        emit BondPurchased(msg.sender, bondAmount, cost);
        emit FundsAllocated("Principal Reserve", cost);
        emit FundsAllocated("Coupon Reserve", couponAllocation);
        emit FundsAllocated("Project Funds", projectAllocation);
        emit FundsAllocated("Emergency Reserve", emergencyAllocation);
    }
    
    /// @notice Calculate claimable coupon amount for an investor
    /// @param investor The address of the investor
    /// @return uint256 The amount of payment tokens claimable as coupon interest
    /// @dev Uses precise calculation with PRECISION_FACTOR
    function calculateClaimableCoupon(address investor) public view returns (uint256) {
        // Early returns for edge cases
        uint256 bondBalance = balanceOf(investor);
        if (bondBalance == 0) return 0;
        
        uint256 lastClaim = lastCouponClaimDate[investor];
        if (lastClaim == 0) return 0;
        
        // Safely calculate time since last claim
        uint256 timeSinceLastClaim;
        if (block.timestamp < lastClaim) {
            // This should never happen, but just in case of timestamp manipulation
            return 0;
        } else {
            timeSinceLastClaim = block.timestamp - lastClaim;
        }
        
        // If no time has passed, no coupon is due
        if (timeSinceLastClaim == 0) return 0;
        
        // We'll use a step-by-step calculation approach to avoid overflows
        
        // Calculate the effective coupon rate (basis points to decimal)
        // 500 basis points (5%) would become 0.05 * PRECISION_FACTOR
        uint256 effectiveRate = couponRate;
        
        // Calculate annual interest for a single token with high precision
        // We divide by 10000 to convert from basis points to actual percentage
        uint256 annualInterestPerToken;
        
        // First calculate (faceValue * effectiveRate) which is safe from overflow
        uint256 interestNumerator = faceValue * effectiveRate;
        
        // Then divide by 10000 to get the actual interest amount
        annualInterestPerToken = interestNumerator / 10000; 
        
        // Calculate daily interest rate (safeguard against division by zero)
        uint256 secondsPerYear = 365 days;
        
        if (secondsPerYear == 0) return 0; // Should never happen, but defensive coding
        
        // Calculate interest per second for a single token
        uint256 interestPerSecondPerToken = annualInterestPerToken / secondsPerYear;
        
        // Calculate interest per second for all tokens held
        uint256 totalInterestPerSecond = interestPerSecondPerToken * bondBalance;
        
        // Calculate total interest accrued over the time period
        uint256 accruedInterest = totalInterestPerSecond * timeSinceLastClaim;
        
        return accruedInterest;
    }
    
    /// @notice Claim accumulated coupon payments
    /// @dev Calculates claimable amount and transfers payment tokens to the investor
    function claimCoupon() external nonReentrant whenNotPaused {
        // Instead of using calculateClaimableCoupon, calculate directly for safety
        uint256 bondBalance = balanceOf(msg.sender);
        if (bondBalance == 0) revert NoCouponAvailable();
        
        uint256 lastClaim = lastCouponClaimDate[msg.sender];
        if (lastClaim == 0) revert NoCouponAvailable();
        
        // Calculate time since last claim
        uint256 timeSinceLastClaim;
        if (block.timestamp <= lastClaim) {
            revert NoCouponAvailable();
        } else {
            timeSinceLastClaim = block.timestamp - lastClaim;
        }
        
        // If no time has passed, no coupon is due
        if (timeSinceLastClaim == 0) revert NoCouponAvailable();
        
        // Calculate annual interest per token (basis points to decimal)
        uint256 annualInterestPerToken = faceValue * couponRate / 10000;
        
        // Calculate interest per second per token
        uint256 secondsPerYear = 365 days;
        if (secondsPerYear == 0) secondsPerYear = 1; // Defensive programming
        
        uint256 interestPerSecondPerToken = annualInterestPerToken / secondsPerYear;
        
        // Calculate interest per second for all tokens
        uint256 interestPerSecondTotal = interestPerSecondPerToken * bondBalance;
        
        // Calculate total claimable coupon
        uint256 claimableAmount = interestPerSecondTotal * timeSinceLastClaim;
        
        if (claimableAmount == 0) revert NoCouponAvailable();
        
        // Update last claim date
        lastCouponClaimDate[msg.sender] = block.timestamp;
        
        // Update treasury accounting with underflow protection
        if (treasury.couponReserve >= claimableAmount) {
            treasury.couponReserve -= claimableAmount;
        } else {
            treasury.couponReserve = 0;
        }
        
        // Check available balance before transfer
        uint256 availableBalance = paymentToken.balanceOf(address(this));
        
        // Ensure we don't try to transfer more than available
        uint256 transferAmount = claimableAmount;
        if (transferAmount > availableBalance) {
            transferAmount = availableBalance;
        }
        
        // Transfer coupon payment
        if (transferAmount > 0) {
            paymentToken.safeTransfer(msg.sender, transferAmount);
        }
        
        emit CouponClaimed(msg.sender, transferAmount);
    }
    
    /// @notice Redeem bonds at maturity
    /// @dev Transfers principal and any outstanding coupon payments to the investor
    function redeemBonds() external nonReentrant whenNotPaused {
        if (block.timestamp < maturityDate) revert BondNotMatured();
        
        uint256 bondAmount = balanceOf(msg.sender);
        if (bondAmount == 0) revert NoBondsToRedeem();
        
        // Calculate redemption value safely
        uint256 redemptionValue = bondAmount * faceValue;
        
        // Calculate claimable coupon safely - without using the potentially problematic calculateClaimableCoupon function
        uint256 claimableAmount = 0;
        uint256 lastClaim = lastCouponClaimDate[msg.sender];
        
        if (lastClaim > 0 && block.timestamp > lastClaim) {
            uint256 timeSinceLastClaim = block.timestamp - lastClaim;
            
            // Calculate annual interest per token (basis points to decimal)
            uint256 annualInterestPerToken = faceValue * couponRate / 10000;
            
            // Calculate interest per second per token - ensure we don't divide by zero
            uint256 secondsPerYear = 365 days;
            if (secondsPerYear == 0) secondsPerYear = 1; // Defensive programming
            
            uint256 interestPerSecondPerToken = annualInterestPerToken / secondsPerYear;
            
            // Calculate total interest for all tokens over time period - calculate in chunks to prevent overflow
            // First multiply by bondAmount, then by time to prevent intermediate overflows
            uint256 interestPerSecond = interestPerSecondPerToken * bondAmount;
            claimableAmount = interestPerSecond * timeSinceLastClaim;
        }
        
        // Update bond holdings by burning ERC20 tokens
        _burn(msg.sender, bondAmount);
        lastCouponClaimDate[msg.sender] = 0;
        
        // Update treasury accounting - ensure we don't underflow
        if (treasury.principalReserve >= redemptionValue) {
            treasury.principalReserve -= redemptionValue;
        } else {
            treasury.principalReserve = 0;
        }
        
        if (claimableAmount > 0) {
            if (treasury.couponReserve >= claimableAmount) {
                treasury.couponReserve -= claimableAmount;
            } else {
                treasury.couponReserve = 0;
            }
        }
        
        // Check available balance before transfer
        uint256 availableBalance = paymentToken.balanceOf(address(this));
        
        // Calculate total payment based on available balance
        uint256 totalPayment = redemptionValue;
        if (claimableAmount > 0) {
            totalPayment = totalPayment + claimableAmount;
        }
        
        // Ensure we don't try to transfer more than available
        if (totalPayment > availableBalance) {
            totalPayment = availableBalance;
        }
        
        // Transfer redemption amount + final coupon (capped by available balance)
        if (totalPayment > 0) {
            paymentToken.safeTransfer(msg.sender, totalPayment);
        }
        
        emit BondRedeemed(msg.sender, bondAmount, totalPayment);
    }
    
    /// @notice Redeem bonds early with a penalty
    /// @param bondAmount Amount of bonds to redeem early
    /// @dev Calculates penalty and transfers reduced amount to investor
    function redeemBondsEarly(uint256 bondAmount) external nonReentrant whenNotPaused {
        if (!earlyRedemptionEnabled) revert EarlyRedemptionNotEnabled();
        if (bondAmount == 0 || bondAmount > balanceOf(msg.sender)) revert InvalidBondAmount();
        
        uint256 redemptionValue = bondAmount * faceValue;
        uint256 penalty = redemptionValue * earlyRedemptionPenaltyBps / 10000;
        uint256 payoutAmount = redemptionValue - penalty;
        
        // Calculate prorated coupon using the safer approach
        uint256 lastClaim = lastCouponClaimDate[msg.sender];
        
        uint256 timeSinceLastClaim;
        if (block.timestamp <= lastClaim) {
            timeSinceLastClaim = 0;
        } else {
            timeSinceLastClaim = block.timestamp - lastClaim;
        }
        
        uint256 proRatedCoupon = 0;
        if (timeSinceLastClaim > 0) {
            // Calculate the effective coupon rate
            uint256 effectiveRate = couponRate;
            
            // Calculate annual interest for the bond amount
            uint256 interestNumerator = bondAmount * faceValue * effectiveRate;
            uint256 annualInterest = interestNumerator / 10000;
            
            // Calculate interest per second
            uint256 secondsPerYear = 365 days;
            if (secondsPerYear == 0) secondsPerYear = 1; // Defensive programming
            
            uint256 interestPerSecond = annualInterest / secondsPerYear;
            
            // Calculate total interest accrued over the time period
            proRatedCoupon = interestPerSecond * timeSinceLastClaim;
        }
        
        // Burn bond tokens
        _burn(msg.sender, bondAmount);
        
        // Update accounting
        if (treasury.principalReserve >= redemptionValue) {
            treasury.principalReserve -= redemptionValue;
        } else {
            treasury.principalReserve = 0;
        }
        treasury.emergencyReserve += penalty; // Penalty goes to emergency reserve
        
        if (proRatedCoupon > 0) {
            if (treasury.couponReserve >= proRatedCoupon) {
                treasury.couponReserve -= proRatedCoupon;
            } else {
                treasury.couponReserve = 0;
            }
        }
        
        // Check available balance before transfer
        uint256 availableBalance = paymentToken.balanceOf(address(this));
        
        // Calculate total payout
        uint256 totalPayout = payoutAmount + proRatedCoupon;
        
        // Ensure we don't try to transfer more than available
        if (totalPayout > availableBalance) {
            totalPayout = availableBalance;
        }
        
        // Transfer funds
        if (totalPayout > 0) {
            paymentToken.safeTransfer(msg.sender, totalPayout);
        }
        
        emit BondRedeemedEarly(msg.sender, bondAmount, totalPayout, penalty);
    }
    
    /// @notice Add a new tranche of bonds with different risk/reward profile
    /// @param _name Name of the tranche
    /// @param _faceValue Face value of each bond in this tranche
    /// @param _couponRate Coupon rate for this tranche in basis points
    /// @param _seniority Seniority level (lower is more senior)
    /// @param _totalSupply Total supply of this tranche
    /// @dev Only callable by issuer
    function addTranche(
        string memory _name,
        uint256 _faceValue,
        uint256 _couponRate,
        uint256 _seniority,
        uint256 _totalSupply
    ) external onlyRole(ISSUER_ROLE) whenNotPaused {
        uint256 trancheId = trancheCount++;
        Tranche storage newTranche = tranches[trancheId];
        
        newTranche.name = _name;
        newTranche.faceValue = _faceValue;
        newTranche.couponRate = _couponRate;
        newTranche.seniority = _seniority;
        newTranche.totalSupply = _totalSupply;
        newTranche.availableSupply = _totalSupply;
        
        emit TrancheAdded(trancheId, _name, _couponRate, _seniority);
    }
    
    /// @notice Purchase bonds from a specific tranche
    /// @param trancheId ID of the tranche to purchase from
    /// @param bondAmount Amount of bonds to purchase
    /// @dev Similar to regular bond purchase but for specific tranches
    function purchaseTrancheBonds(uint256 trancheId, uint256 bondAmount) external nonReentrant whenNotPaused {
        if (trancheId >= trancheCount) revert TrancheDoesNotExist();
        Tranche storage tranche = tranches[trancheId];
        
        if (block.timestamp >= maturityDate) revert BondMatured();
        if (bondAmount == 0) revert InvalidBondAmount();
        if (bondAmount > tranche.availableSupply) revert InsufficientBondsAvailable();
        
        // Calculate cost safely
        uint256 cost = bondAmount * tranche.faceValue;
        
        // Transfer payment tokens from buyer to contract
        paymentToken.safeTransferFrom(msg.sender, address(this), cost);
        
        // Update tranche holdings
        tranche.holdings[msg.sender] += bondAmount;
        tranche.availableSupply -= bondAmount;
        tranche.lastCouponClaimDate[msg.sender] = block.timestamp;
        
        // Allocate funds to different reserves - safely breaking down calculations
        uint256 timeToMaturity = 0;
        if (maturityDate > block.timestamp) {
            timeToMaturity = maturityDate - block.timestamp;
        }
        
        uint256 couponAllocation = 0;
        if (timeToMaturity > 0) {
            // Calculate annual coupon
            uint256 annualCouponPercentage = tranche.couponRate;
            uint256 annualCouponAmount = cost * annualCouponPercentage / 10000;
            
            // Calculate time-proportional coupon allocation
            uint256 secondsPerYear = 365 days;
            couponAllocation = (annualCouponAmount * timeToMaturity) / secondsPerYear;
        }
        
        // Update treasury balances
        treasury.principalReserve += cost;
        treasury.couponReserve += couponAllocation;
        
        uint256 remainingAmount = cost - couponAllocation;
        uint256 projectAllocation = (remainingAmount * 90) / 100;  // 90% for project
        uint256 emergencyAllocation = remainingAmount - projectAllocation; // Remainder for emergency
        
        treasury.projectFunds += projectAllocation;
        treasury.emergencyReserve += emergencyAllocation;
        
        emit TrancheBondPurchased(msg.sender, trancheId, bondAmount, cost);
        emit FundsAllocated("Principal Reserve", cost);
        emit FundsAllocated("Coupon Reserve", couponAllocation);
    }
    
    /// @notice Calculate claimable coupon for a tranche bondholder
    /// @param trancheId ID of the tranche
    /// @param investor Address of the investor
    /// @return uint256 Claimable coupon amount
    function calculateTrancheCoupon(uint256 trancheId, address investor) public view returns (uint256) {
        if (trancheId >= trancheCount) revert TrancheDoesNotExist();
        Tranche storage tranche = tranches[trancheId];
        
        // Early returns for edge cases
        uint256 bondBalance = tranche.holdings[investor];
        if (bondBalance == 0) return 0;
        
        uint256 lastClaim = tranche.lastCouponClaimDate[investor];
        if (lastClaim == 0) return 0;
        
        // Safely calculate time since last claim
        uint256 timeSinceLastClaim;
        if (block.timestamp < lastClaim) {
            // This should never happen, but just in case of timestamp manipulation
            return 0;
        } else {
            timeSinceLastClaim = block.timestamp - lastClaim;
        }
        
        // If no time has passed, no coupon is due
        if (timeSinceLastClaim == 0) return 0;
        
        // Calculate the effective coupon rate (basis points to decimal)
        uint256 effectiveRate = tranche.couponRate;
        
        // Calculate annual interest for a single token
        // We divide by 10000 to convert from basis points to actual percentage
        uint256 interestNumerator = tranche.faceValue * effectiveRate;
        uint256 annualInterestPerToken = interestNumerator / 10000;
        
        // Calculate interest per second for a single token
        uint256 secondsPerYear = 365 days;
        uint256 interestPerSecondPerToken = annualInterestPerToken / secondsPerYear;
        
        // Calculate interest per second for all tokens held
        uint256 totalInterestPerSecond = interestPerSecondPerToken * bondBalance;
        
        // Calculate total interest accrued over the time period
        uint256 accruedInterest = totalInterestPerSecond * timeSinceLastClaim;
        
        return accruedInterest;
    }
    
    /// @notice Claim coupon for a specific tranche
    /// @param trancheId ID of the tranche
    function claimTrancheCoupon(uint256 trancheId) external nonReentrant whenNotPaused {
        if (trancheId >= trancheCount) revert TrancheDoesNotExist();
        Tranche storage tranche = tranches[trancheId];
        
        uint256 bondBalance = tranche.holdings[msg.sender];
        if (bondBalance == 0) revert NoCouponAvailable();
        
        uint256 lastClaim = tranche.lastCouponClaimDate[msg.sender];
        if (lastClaim == 0) revert NoCouponAvailable();
        
        // Calculate time since last claim
        uint256 timeSinceLastClaim;
        if (block.timestamp <= lastClaim) {
            revert NoCouponAvailable();
        } else {
            timeSinceLastClaim = block.timestamp - lastClaim;
        }
        
        // If no time has passed, no coupon is due
        if (timeSinceLastClaim == 0) revert NoCouponAvailable();
        
        // Calculate annual interest per token (basis points to decimal)
        uint256 annualInterestPerToken = tranche.faceValue * tranche.couponRate / 10000;
        
        // Calculate interest per second per token
        uint256 secondsPerYear = 365 days;
        if (secondsPerYear == 0) secondsPerYear = 1; // Defensive programming
        
        uint256 interestPerSecondPerToken = annualInterestPerToken / secondsPerYear;
        
        // Calculate interest per second for all tokens
        uint256 interestPerSecondTotal = interestPerSecondPerToken * bondBalance;
        
        // Calculate total claimable coupon
        uint256 claimableAmount = interestPerSecondTotal * timeSinceLastClaim;
        
        if (claimableAmount == 0) revert NoCouponAvailable();
        
        // Update last claim date
        tranche.lastCouponClaimDate[msg.sender] = block.timestamp;
        
        // Update treasury accounting with underflow protection
        if (treasury.couponReserve >= claimableAmount) {
            treasury.couponReserve -= claimableAmount;
        } else {
            treasury.couponReserve = 0;
        }
        
        // Check available balance before transfer
        uint256 availableBalance = paymentToken.balanceOf(address(this));
        
        // Ensure we don't try to transfer more than available
        uint256 transferAmount = claimableAmount;
        if (transferAmount > availableBalance) {
            transferAmount = availableBalance;
        }
        
        // Transfer coupon payment
        if (transferAmount > 0) {
            paymentToken.safeTransfer(msg.sender, transferAmount);
        }
        
        emit TrancheCouponClaimed(msg.sender, trancheId, transferAmount);
    }
    
    /// @notice Redeem bonds from a specific tranche
    /// @param trancheId ID of the tranche
    function redeemTrancheBonds(uint256 trancheId) external nonReentrant whenNotPaused {
        if (trancheId >= trancheCount) revert TrancheDoesNotExist();
        Tranche storage tranche = tranches[trancheId];
        
        if (block.timestamp < maturityDate) revert BondNotMatured();
        
        uint256 bondAmount = tranche.holdings[msg.sender];
        if (bondAmount == 0) revert NoBondsToRedeem();
        
        // Calculate redemption value safely
        uint256 redemptionValue = bondAmount * tranche.faceValue;
        
        // Calculate claimable coupon safely - inline calculation instead of using the function
        uint256 claimableAmount = 0;
        uint256 lastClaim = tranche.lastCouponClaimDate[msg.sender];
        
        if (lastClaim > 0 && block.timestamp > lastClaim) {
            uint256 timeSinceLastClaim = block.timestamp - lastClaim;
            
            // Calculate annual interest per token (basis points to decimal)
            uint256 annualInterestPerToken = tranche.faceValue * tranche.couponRate / 10000;
            
            // Calculate interest per second per token
            uint256 secondsPerYear = 365 days;
            if (secondsPerYear == 0) secondsPerYear = 1; // Defensive programming
            
            uint256 interestPerSecondPerToken = annualInterestPerToken / secondsPerYear;
            
            // Break down multiplication to prevent overflow
            uint256 interestPerSecond = interestPerSecondPerToken * bondAmount;
            claimableAmount = interestPerSecond * timeSinceLastClaim;
        }
        
        // Update holdings
        tranche.holdings[msg.sender] = 0;
        tranche.lastCouponClaimDate[msg.sender] = 0;
        
        // Update treasury accounting - with overflow protection
        if (treasury.principalReserve >= redemptionValue) {
            treasury.principalReserve -= redemptionValue;
        } else {
            treasury.principalReserve = 0;
        }
        
        if (claimableAmount > 0) {
            if (treasury.couponReserve >= claimableAmount) {
                treasury.couponReserve -= claimableAmount;
            } else {
                treasury.couponReserve = 0;
            }
        }
        
        // Check available balance before transfer
        uint256 availableBalance = paymentToken.balanceOf(address(this));
        
        // Calculate total payment based on available balance
        uint256 totalPayment = redemptionValue;
        if (claimableAmount > 0) {
            totalPayment = totalPayment + claimableAmount;
        }
        
        // Ensure we don't try to transfer more than available
        if (totalPayment > availableBalance) {
            totalPayment = availableBalance;
        }
        
        // Transfer redemption amount + final coupon (capped by available balance)
        if (totalPayment > 0) {
            paymentToken.safeTransfer(msg.sender, totalPayment);
        }
        
        emit TrancheBondRedeemed(msg.sender, trancheId, bondAmount, totalPayment);
    }
    
    /// @notice Add environmental impact report with enhanced metrics
    /// @param reportURI URI pointing to the full report document
    /// @param reportHash Hash of the report for verification
    /// @param impactMetricsJson JSON string containing detailed metrics
    /// @param metricNames Array of metric names for quantitative tracking
    /// @param metricValues Array of corresponding metric values
    /// @param challengePeriod Duration in seconds for challenge period
    /// @param requiredVerifications Number of verifiers required to finalize
    /// @dev Only callable by issuer
    function addEnhancedImpactReport(
        string memory reportURI,
        string memory reportHash,
        string memory impactMetricsJson,
        string[] memory metricNames,
        uint256[] memory metricValues,
        uint256 challengePeriod,
        uint256 requiredVerifications
    ) external onlyRole(ISSUER_ROLE) whenNotPaused {
        require(metricNames.length == metricValues.length, "Arrays length mismatch");
        
        uint256 reportId = impactReportCount++;
        EnhancedImpactReport storage newReport = impactReports[reportId];
        
        newReport.reportURI = reportURI;
        newReport.reportHash = reportHash;
        newReport.timestamp = block.timestamp;
        newReport.impactMetricsJson = impactMetricsJson;
        newReport.challengePeriodEnd = block.timestamp + challengePeriod;
        newReport.requiredVerifications = requiredVerifications;
        newReport.finalized = false;
        
        // Store quantitative metrics
        for (uint256 i = 0; i < metricNames.length; i++) {
            newReport.quantitativeMetrics[metricNames[i]] = metricValues[i];
            newReport.metricNames.push(metricNames[i]);
        }
        
        emit ImpactReportAdded(reportId, reportURI);
        emit ImpactMetricsAchieved(reportId, metricNames, metricValues, block.timestamp);
    }
    
    /// @notice Verify an impact report
    /// @param reportId ID of the report to verify
    /// @dev Requires multiple verifications to finalize
    function verifyImpactReport(uint256 reportId) external onlyRole(VERIFIER_ROLE) whenNotPaused {
        if (reportId >= impactReportCount) revert ReportDoesNotExist();
        
        EnhancedImpactReport storage report = impactReports[reportId];
        if (report.finalized) revert ReportAlreadyVerified();
        if (block.timestamp > report.challengePeriodEnd) revert ChallengePeriodEnded();
        if (report.hasVerified[msg.sender]) revert AlreadyVoted();
        
        report.hasVerified[msg.sender] = true;
        report.verificationCount++;
        
        emit ImpactReportVerified(reportId, msg.sender);
        
        // Check if report has reached required verifications
        if (report.verificationCount >= report.requiredVerifications) {
            report.finalized = true;
            emit ImpactReportFinalized(reportId);
            
            // Update green premium based on impact metrics
            if (greenPremiumRate < (maxCouponRate - baseCouponRate)) {
                uint256 oldCouponRate = couponRate;
                greenPremiumRate += 50; // Increase by 0.5%
                couponRate = baseCouponRate + greenPremiumRate;
                
                emit CouponRateUpdated(couponRate);
                emit BondParametersUpdated(oldCouponRate, couponRate, couponPeriod, couponPeriod);
            }
        }
    }
    
    /// @notice Challenge an impact report
    /// @param reportId ID of the report to challenge
    /// @param reason Reason for the challenge
    /// @dev Prevents finalization and requires review
    function challengeImpactReport(uint256 reportId, string memory reason) external onlyRole(VERIFIER_ROLE) whenNotPaused {
        if (reportId >= impactReportCount) revert ReportDoesNotExist();
        
        EnhancedImpactReport storage report = impactReports[reportId];
        if (report.finalized) revert ReportAlreadyVerified();
        if (block.timestamp > report.challengePeriodEnd) revert ChallengePeriodEnded();
        
        // Extend challenge period and reset verification count
        report.challengePeriodEnd = block.timestamp + 7 days;
        report.verificationCount = 0;
        
        // Reset all verifications
        for (uint256 i = 0; i < report.verificationCount; i++) {
            address verifier = msg.sender; 
            report.hasVerified[verifier] = false;
        }
        
        emit ImpactReportChallenged(reportId, msg.sender, reason);
    }
    
    /// @notice Get an impact report's quantitative metrics
    /// @param reportId ID of the report
    /// @param metricName Name of the metric
    /// @return uint256 Value of the requested metric
    function getImpactMetricValue(uint256 reportId, string memory metricName) external view returns (uint256) {
        if (reportId >= impactReportCount) revert ReportDoesNotExist();
        return impactReports[reportId].quantitativeMetrics[metricName];
    }
    
    /// @notice Get all metric names for a report
    /// @param reportId ID of the report
    /// @return string[] Array of metric names
    function getImpactMetricNames(uint256 reportId) external view returns (string[] memory) {
        if (reportId >= impactReportCount) revert ReportDoesNotExist();
        return impactReports[reportId].metricNames;
    }
    
    /// @notice Create a governance proposal
    /// @param description Description of the proposal
    /// @param target Contract address to call if proposal passes
    /// @param callData Function call data to execute
    /// @dev Only callable by issuer
    function createProposal(string memory description, address target, bytes memory callData) 
        external 
        onlyRole(ISSUER_ROLE) 
        whenNotPaused
        returns (uint256) 
    {
        uint256 proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        
        proposal.proposer = msg.sender;
        proposal.description = description;
        proposal.target = target;
        proposal.callData = callData;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp + votingPeriod;
        proposal.executed = false;
        
        emit ProposalCreated(proposalId, msg.sender, description);
        return proposalId;
    }
    
    /// @notice Cast a vote on a proposal
    /// @param proposalId ID of the proposal
    /// @param support Whether to support the proposal
    /// @dev Voting power is proportional to bond holdings
    function castVote(uint256 proposalId, bool support) external whenNotPaused {
        if (proposalId >= proposalCount) revert ProposalDoesNotExist();
        
        Proposal storage proposal = proposals[proposalId];
        if (block.timestamp > proposal.endTime) revert VotingPeriodEnded();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (proposal.hasVoted[msg.sender]) revert AlreadyVoted();
        
        uint256 votingPower = balanceOf(msg.sender);
        require(votingPower > 0, "No voting power");
        
        proposal.hasVoted[msg.sender] = true;
        
        if (support) {
            proposal.forVotes += votingPower;
        } else {
            proposal.againstVotes += votingPower;
        }
        
        emit VoteCast(msg.sender, proposalId, support, votingPower);
    }
    
    /// @notice Execute a successful proposal
    /// @param proposalId ID of the proposal
    /// @dev Only executable after voting period and if quorum is reached
    function executeProposal(uint256 proposalId) external nonReentrant whenNotPaused {
        if (proposalId >= proposalCount) revert ProposalDoesNotExist();
        
        Proposal storage proposal = proposals[proposalId];
        if (block.timestamp <= proposal.endTime) revert VotingPeriodEnded();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        
        // Check if quorum is met and proposal passed
        if (proposal.forVotes + proposal.againstVotes < quorum) revert QuorumNotReached();
        require(proposal.forVotes > proposal.againstVotes, "Proposal rejected");
        
        proposal.executed = true;
        
        // Execute the proposal
        (bool success, ) = proposal.target.call(proposal.callData);
        if (!success) revert FailedExecution();
        
        emit ProposalExecuted(proposalId);
    }
    
    /// @notice Update coupon period
    /// @param newCouponPeriod New period in seconds
    /// @dev Only callable by issuer with timelock
    function updateCouponPeriod(uint256 newCouponPeriod) 
        external 
        onlyRole(ISSUER_ROLE)
        whenNotPaused 
    {
        bytes32 operationId = keccak256(abi.encodePacked("updateCouponPeriod", newCouponPeriod, block.timestamp));
        
        if (operationTimestamps[operationId] == 0) {
            scheduleOperation(operationId);
            return;
        }
        
        if (block.timestamp < operationTimestamps[operationId]) revert TimelockNotExpired();
        
        uint256 oldCouponPeriod = couponPeriod;
        couponPeriod = newCouponPeriod;
        
        emit BondParametersUpdated(couponRate, couponRate, oldCouponPeriod, couponPeriod);
    }
    
    /// @notice Set early redemption parameters
    /// @param enabled Whether early redemption is enabled
    /// @param penaltyBps Penalty in basis points for early redemption
    /// @dev Only callable by issuer
    function setEarlyRedemptionParams(bool enabled, uint256 penaltyBps) external onlyRole(ISSUER_ROLE) whenNotPaused {
        earlyRedemptionEnabled = enabled;
        earlyRedemptionPenaltyBps = penaltyBps;
        
        emit EarlyRedemptionStatusChanged(enabled);
    }
    
    /// @notice Set the dashboard contract address
    /// @param _dashboardContract Address of dashboard contract
    /// @dev Only callable by admin
    function setDashboardContract(address _dashboardContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        dashboardContract = _dashboardContract;
        emit DashboardContractUpdated(_dashboardContract);
    }
    
    /// @notice Allocate funds to a project component
    /// @param projectComponent Name of component
    /// @param amount Amount to allocate
    /// @dev Records allocation in events but doesn't actually move funds
    function allocateFunds(string memory projectComponent, uint256 amount) 
        external 
        onlyRole(TREASURY_ROLE) 
        whenNotPaused 
    {
        require(amount <= treasury.projectFunds, "Insufficient project funds");
        
        treasury.projectFunds -= amount;
        emit FundsAllocated(projectComponent, amount);
    }
    
