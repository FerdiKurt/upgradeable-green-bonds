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
    error NoVotingPower();
    error ArrayLengthMismatch();
    error ProposalRejected();
    error InvalidValue();
    error EmptyString();
    error RateExceedsMaximum();
    error RecoveryNotAuthorized();
    error InvalidRecoveryAmount();
    error OperationAlreadyExecuted();

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
    uint256 public bondTotalSupply;
    uint256 public availableSupply;
    uint256 public baseCouponRate; // Base rate in basis points (e.g., 500 = 5.00%)
    uint256 public greenPremiumRate; // Additional rate based on green performance
    uint256 public maxCouponRate; // Cap on total rate
    uint256 public couponRate; // Current effective rate (base + green premium)
    uint256 public couponPeriod; // in seconds
    uint256 public maturityDate;
    uint256 public issuanceDate;
    bool private maturityEmitted; // Flag to track if maturity event has been emitted
    
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

    // Allocation percentages in basis points (e.g., 4500 = 45%)
    uint256 public principalAllocationBps;
    uint256 public projectAllocationBps;
    uint256 public emergencyAllocationBps;
    
    // Early redemption parameters
    uint256 public earlyRedemptionPenaltyBps; // Penalty in basis points
    bool public earlyRedemptionEnabled;
    
    // Green project details
    string public projectDescription;
    string public impactMetrics;
    string[] public greenCertifications;
    
    // Impact reports
    struct ImpactReport {
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
        address[] verifiers; 
    }
    
    // Impact reports storage
    mapping(uint256 => ImpactReport) public impactReports;
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
        string category,
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
    event GovernanceParamsUpdated(uint256 oldQuorum, uint256 newQuorum, uint256 oldVotingPeriod, uint256 newVotingPeriod);
    event GreenCertificationAdded(string certification, uint256 index);
    event OperationExecuted(bytes32 indexed operationId);
    event FundsDeducted(string reserve, uint256 amount);
    event ChallengePeriodExtended(uint256 indexed reportId, uint256 newEndTime);
    event VerificationRequirementsReset(uint256 indexed reportId);
    event EarlyRedemptionPenaltyUpdated(uint256 oldPenaltyBps, uint256 newPenaltyBps);
    event BondMaturityReached(uint256 maturityDate);
    event BaseCouponRateUpdated(uint256 oldRate, uint256 newRate);
    event GreenPremiumRateUpdated(uint256 oldRate, uint256 newRate);
    event TrancheTransfer(uint256 indexed trancheId, address indexed from, address indexed to, uint256 amount);
    event EmergencyRecovery(address indexed recipient, uint256 amount);
    event AllocationPercentagesUpdated(
        uint256 oldPrincipalAllocationBps,
        uint256 newPrincipalAllocationBps,
        uint256 oldProjectAllocationBps,
        uint256 newProjectAllocationBps,
        uint256 oldEmergencyAllocationBps,
        uint256 newEmergencyAllocationBps
    );
    
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
        maturityEmitted = false;
        paymentToken = IERC20(_paymentTokenAddress);
        projectDescription = _projectDescription;
        impactMetrics = _impactMetrics;

        // Initialize allocation percentages 
        principalAllocationBps = 4500; // 45%
        projectAllocationBps = 5000;   // 50%
        emergencyAllocationBps = 500;  // 5%
        
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
    
    /**
    * @notice Checks operation status and schedules or executes based on timelock conditions
    * @dev This function handles the complete lifecycle of a timelocked operation
    * @param operationId The unique identifier for the operation to check/schedule
    * @return bool Returns true if operation is ready for execution, false if newly scheduled
    */
    function checkAndScheduleOperation(bytes32 operationId) internal returns (bool) {
        if (isOperationExecuted[operationId]) {
            revert OperationAlreadyExecuted();
        }
        
        if (operationTimestamps[operationId] == 0) {
            scheduleOperation(operationId);
            return false;
        }
        
        if (block.timestamp < operationTimestamps[operationId]) {
            revert TimelockNotExpired();
        }
        
        isOperationExecuted[operationId] = true;
        return true;
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
        uint256 index = greenCertifications.length;
        greenCertifications.push(certification);
        emit GreenCertificationAdded(certification, index);
    }
    
    /// @notice Check if the bond is matured
    /// @return bool True if matured, false otherwise
    function isBondMatured() internal view returns (bool) {
        return block.timestamp >= maturityDate;
    }
    
    /// @notice Check and emit maturity event if bond has matured
    function checkAndEmitMaturity() internal {
        if (block.timestamp >= maturityDate && !maturityEmitted) {
            maturityEmitted = true;
            emit BondMaturityReached(maturityDate);
        }
    }

    /// @notice Update allocation percentages
    /// @param _principalAllocationBps Percentage for principal reserve in basis points
    /// @param _projectAllocationBps Percentage for project funds in basis points
    /// @param _emergencyAllocationBps Percentage for emergency reserve in basis points
    /// @dev Only callable by admin
    function updateAllocationPercentages(
        uint256 _principalAllocationBps,
        uint256 _projectAllocationBps,
        uint256 _emergencyAllocationBps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        // Validate that percentages sum to 10000 (100%)
        if (_principalAllocationBps + _projectAllocationBps + _emergencyAllocationBps != 10000) revert InvalidValue();
        
        // Store old values for event
        uint256 oldPrincipalAllocationBps = principalAllocationBps;
        uint256 oldProjectAllocationBps = projectAllocationBps;
        uint256 oldEmergencyAllocationBps = emergencyAllocationBps;
        
        // Update percentages
        principalAllocationBps = _principalAllocationBps;
        projectAllocationBps = _projectAllocationBps;
        emergencyAllocationBps = _emergencyAllocationBps;
        
        // Emit event
        emit AllocationPercentagesUpdated(
            oldPrincipalAllocationBps,
            principalAllocationBps,
            oldProjectAllocationBps,
            projectAllocationBps,
            oldEmergencyAllocationBps,
            emergencyAllocationBps
        );
    }
    
    /// @notice Update treasury balances
    /// @param principal Amount to add to principal reserve
    /// @param coupon Amount to add to coupon reserve
    /// @param project Amount to add to project funds
    /// @param emergency Amount to add to emergency reserve
    /// @dev Internal function to update treasury balances
    function updateTreasury(
        int256 principal,
        int256 coupon,
        int256 project,
        int256 emergency
    ) internal {
        // Handle principal reserve
        if (principal > 0) {
            treasury.principalReserve += uint256(principal);
            emit FundsAllocated("Principal Reserve", uint256(principal));
        } else if (principal < 0) {
            uint256 amount = uint256(-principal);
            if (treasury.principalReserve >= amount) {
                treasury.principalReserve -= amount;
                emit FundsDeducted("Principal Reserve", amount);
            } else {
                uint256 oldValue = treasury.principalReserve;
                treasury.principalReserve = 0;
                emit FundsDeducted("Principal Reserve", oldValue);
            }
        }
        
        // Handle coupon reserve
        if (coupon > 0) {
            treasury.couponReserve += uint256(coupon);
            emit FundsAllocated("Coupon Reserve", uint256(coupon));
        } else if (coupon < 0) {
            uint256 amount = uint256(-coupon);
            if (treasury.couponReserve >= amount) {
                treasury.couponReserve -= amount;
                emit FundsDeducted("Coupon Reserve", amount);
            } else {
                uint256 oldValue = treasury.couponReserve;
                treasury.couponReserve = 0;
                emit FundsDeducted("Coupon Reserve", oldValue);
            }
        }
        
        // Handle project funds
        if (project > 0) {
            treasury.projectFunds += uint256(project);
            emit FundsAllocated("Project Funds", uint256(project));
        } else if (project < 0) {
            uint256 amount = uint256(-project);
            if (treasury.projectFunds >= amount) {
                treasury.projectFunds -= amount;
                emit FundsDeducted("Project Funds", amount);
            } else {
                uint256 oldValue = treasury.projectFunds;
                treasury.projectFunds = 0;
                emit FundsDeducted("Project Funds", oldValue);
            }
        }
        
        // Handle emergency reserve
        if (emergency > 0) {
            treasury.emergencyReserve += uint256(emergency);
            emit FundsAllocated("Emergency Reserve", uint256(emergency));
        } else if (emergency < 0) {
            uint256 amount = uint256(-emergency);
            if (treasury.emergencyReserve >= amount) {
                treasury.emergencyReserve -= amount;
                emit FundsDeducted("Emergency Reserve", amount);
            } else {
                uint256 oldValue = treasury.emergencyReserve;
                treasury.emergencyReserve = 0;
                emit FundsDeducted("Emergency Reserve", oldValue);
            }
        }
    }
    
    /// @notice Safe transfer of tokens
    /// @param recipient Address to receive tokens
    /// @param amount Amount to transfer
    /// @return uint256 Amount actually transferred
    /// @dev Safely transfers tokens respecting available balance
    function safeTransferTokens(address recipient, uint256 amount) internal returns (uint256) {
        uint256 availableBalance = paymentToken.balanceOf(address(this));
        
        // Ensure we don't try to transfer more than available
        uint256 transferAmount = amount;
        if (transferAmount > availableBalance) {
            transferAmount = availableBalance;
        }
        
        // Transfer tokens
        paymentToken.safeTransfer(recipient, transferAmount);

        return transferAmount;
    }
    
    /// @notice Calculate time-based interest (core coupon calculation logic)
    /// @param lastClaim Time of last claim
    /// @param effectiveRate Coupon rate in basis points
    /// @param tokenValue Face value of each token
    /// @param tokenAmount Number of tokens
    /// @return uint256 Interest amount
    function calculateTimeBasedInterest(
        uint256 lastClaim,
        uint256 effectiveRate,
        uint256 tokenValue,
        uint256 tokenAmount
    ) internal view returns (uint256) {
        // Early returns for edge cases
        if (tokenAmount == 0 || lastClaim == 0) return 0;
        
        // Calculate time since last claim
        uint256 timeSinceLastClaim;
        if (block.timestamp <= lastClaim) {
            return 0;
        } else {
            // Using unchecked since block.timestamp > lastClaim is already verified
            unchecked {
                timeSinceLastClaim = block.timestamp - lastClaim;
            }
        }
        
        // If no time has passed, no interest is due
        if (timeSinceLastClaim == 0) return 0;
        
        // Calculate annual interest per token (basis points to decimal)
        uint256 annualInterestPerToken;
        unchecked {
            annualInterestPerToken = tokenValue * effectiveRate / 10000;
        }
        
        // Calculate interest per second per token
        uint256 secondsPerYear = 365 days;
        if (secondsPerYear == 0) secondsPerYear = 1;
        
        uint256 interestPerSecondPerToken;
        uint256 totalInterestPerSecond;
        uint256 totalInterest;
        
        unchecked {
            interestPerSecondPerToken = annualInterestPerToken / secondsPerYear;
            totalInterestPerSecond = interestPerSecondPerToken * tokenAmount;
            totalInterest = totalInterestPerSecond * timeSinceLastClaim;
        }
        
        return totalInterest;
    }
    
    /// @notice Calculate claimable coupon for standard bonds
    /// @param investor Address of the investor
    /// @return uint256 Claimable coupon amount
    function calculateClaimableCoupon(address investor) public view returns (uint256) {
        return calculateTimeBasedInterest(
            lastCouponClaimDate[investor],
            couponRate,
            faceValue,
            balanceOf(investor)
        );
    }
    
    /// @notice Calculate claimable coupon for tranche bonds
    /// @param trancheId ID of the tranche
    /// @param investor Address of the investor
    /// @return uint256 Claimable coupon amount
    function calculateTrancheCoupon(uint256 trancheId, address investor) public view returns (uint256) {
        if (trancheId >= trancheCount) revert TrancheDoesNotExist();
        Tranche storage tranche = tranches[trancheId];
        
        return calculateTimeBasedInterest(
            tranche.lastCouponClaimDate[investor],
            tranche.couponRate,
            tranche.faceValue,
            tranche.holdings[investor]
        );
    }
    
    /// @notice Process a bond purchase (generic for both standard and tranche)
    /// @param bondAmount Amount of bonds to purchase
    /// @param cost Total cost of bonds
    /// @param isTranche Whether this is a tranche purchase
    /// @param trancheId ID of the tranche (if applicable)
    /// @dev Internal function to handle bond purchase logic
    function processBondPurchase(
        uint256 bondAmount,
        uint256 cost,
        bool isTranche,
        uint256 trancheId
    ) internal {
        // Check for maturity and emit event if needed
        checkAndEmitMaturity();
        
        uint256 currentTime = block.timestamp;
        
        // Transfer payment tokens from buyer to contract
        paymentToken.safeTransferFrom(msg.sender, address(this), cost);
        
        // Calculate allocation for coupon payments
        uint256 couponAllocation = 0;
        if (maturityDate > currentTime) {
            // Calculate annual coupon payment
            uint256 annualCouponAmount = (cost * couponRate) / 10000;
            
            // Calculate time-proportional allocation
            uint256 timeToMaturity = maturityDate - currentTime;
            uint256 secondsPerYear = 365 days;
            couponAllocation = (annualCouponAmount * timeToMaturity) / secondsPerYear;
        }
        
        // Calculate remaining amount after coupon allocation
        uint256 remainingAfterCoupon = cost - couponAllocation;
        
        // Allocate remaining funds 
        uint256 principalAllocation = (remainingAfterCoupon * principalAllocationBps) / 10000;
        uint256 projectAllocation = (remainingAfterCoupon * projectAllocationBps) / 10000;
        
        // Use the emergency allocation percentage or calculate as remainder
        // This handles potential rounding errors to ensure total allocation equals cost
        uint256 emergencyAllocation = remainingAfterCoupon - principalAllocation - projectAllocation;
        
        // Update treasury balances
        updateTreasury(
            int256(principalAllocation),
            int256(couponAllocation),
            int256(projectAllocation),
            int256(emergencyAllocation)
        );
        
        // Update bond state
        if (isTranche) {
            Tranche storage tranche = tranches[trancheId];
            tranche.holdings[msg.sender] += bondAmount;
            tranche.availableSupply = tranche.availableSupply - bondAmount;
            tranche.lastCouponClaimDate[msg.sender] = currentTime;
            
            emit TrancheBondPurchased(msg.sender, trancheId, bondAmount, cost);
        } else {
            _mint(msg.sender, bondAmount);
            availableSupply -= bondAmount;
            lastCouponClaimDate[msg.sender] = currentTime;
            
            emit BondPurchased(msg.sender, bondAmount, cost);
        }
    }
    
    /// @notice Process a coupon claim (generic for both standard and tranche)
    /// @param claimableAmount Amount of coupon to claim
    /// @param investor Address of the investor claiming coupon
    /// @param isTranche Whether this is a tranche claim
    /// @param trancheId ID of the tranche (if applicable)
    /// @return uint256 Amount actually paid
    function processCouponClaim(
        uint256 claimableAmount,
        address investor,
        bool isTranche,
        uint256 trancheId
    ) internal returns (uint256) {
        // Check for maturity and emit event if needed
        checkAndEmitMaturity();
        
        uint256 currentTime = block.timestamp;
        
        // Update treasury
        updateTreasury(
            0,                       // Principal reserve (no change)
            -int256(claimableAmount), // Deduct from coupon reserve
            0,                       // Project funds (no change)
            0                        // Emergency reserve (no change)
        );
        
        // Transfer coupon payment
        uint256 transferAmount = safeTransferTokens(investor, claimableAmount);
        
        // Update last claim date
        if (isTranche) {
            tranches[trancheId].lastCouponClaimDate[investor] = currentTime;
            emit TrancheCouponClaimed(investor, trancheId, transferAmount);
        } else {
            lastCouponClaimDate[investor] = currentTime;
            emit CouponClaimed(investor, transferAmount);
        }
        
        return transferAmount;
    }
    
    /// @notice Process bond redemption (generic for both standard and tranche)
    /// @param bondAmount Amount of bonds to redeem
    /// @param tokenValue Face value of each bond
    /// @param couponAmount Accrued coupon amount
    /// @param investor Address of the investor
    /// @param isTranche Whether this is a tranche redemption
    /// @param trancheId ID of the tranche (if applicable)
    /// @param isEarly Whether this is an early redemption
    /// @param penalty Penalty amount for early redemption (if applicable)
    /// @return uint256 Total amount paid
    function processBondRedemption(
        uint256 bondAmount,
        uint256 tokenValue,
        uint256 couponAmount,
        address investor,
        bool isTranche,
        uint256 trancheId,
        bool isEarly,
        uint256 penalty
    ) internal returns (uint256) {
        // Check for maturity and emit event if needed
        checkAndEmitMaturity();
        
        // Calculate redemption value
        uint256 redemptionValue = bondAmount * tokenValue;
        uint256 payoutAmount = redemptionValue;
        
        if (isEarly) {
            payoutAmount = redemptionValue - penalty;
        }
        
        // Update bond holdings
        if (isTranche) {
            Tranche storage tranche = tranches[trancheId];
            tranche.holdings[investor] = 0;
            tranche.lastCouponClaimDate[investor] = 0;
        } else {
            _burn(investor, bondAmount);
            lastCouponClaimDate[investor] = 0;
        }
        
        // Update treasury accounting
        int256 principalAdjustment = -int256(redemptionValue);
        int256 couponAdjustment = couponAmount > 0 ? -int256(couponAmount) : int256(0);
        int256 emergencyAdjustment = penalty > 0 ? int256(penalty) : int256(0);
        
        updateTreasury(
            principalAdjustment,
            couponAdjustment,
            0,                   // Project funds (no change)
            emergencyAdjustment
        );
        
        // Calculate total payment
        uint256 totalPayment = payoutAmount;
        if (couponAmount > 0) {
            totalPayment = totalPayment + couponAmount;
        }
        
        // Transfer funds
        uint256 transferAmount = safeTransferTokens(investor, totalPayment);
        
        // Emit appropriate event
        if (isTranche) {
            emit TrancheBondRedeemed(investor, trancheId, bondAmount, transferAmount);
        } else if (isEarly) {
            emit BondRedeemedEarly(investor, bondAmount, transferAmount, penalty);
        } else {
            emit BondRedeemed(investor, bondAmount, transferAmount);
        }
        
        return transferAmount;
    }
    
    /// @notice Purchase bonds with payment tokens
    /// @param bondAmount The number of bonds to purchase
    /// @dev Transfers payment tokens from buyer to contract and mints ERC20 tokens
    function purchaseBonds(uint256 bondAmount) external nonReentrant whenNotPaused {
        if (isBondMatured()) revert BondMatured();
        if (bondAmount == 0) revert InvalidBondAmount();
        if (bondAmount > availableSupply) revert InsufficientBondsAvailable();
        
        uint256 cost = bondAmount * faceValue;
        
        processBondPurchase(bondAmount, cost, false, 0);
    }
    
    /// @notice Purchase bonds from a specific tranche
    /// @param trancheId ID of the tranche to purchase from
    /// @param bondAmount Amount of bonds to purchase
    /// @dev Similar to regular bond purchase but for specific tranches
    function purchaseTrancheBonds(uint256 trancheId, uint256 bondAmount) external nonReentrant whenNotPaused {
        if (trancheId >= trancheCount) revert TrancheDoesNotExist();
        Tranche storage tranche = tranches[trancheId];
        
        if (isBondMatured()) revert BondMatured();
        if (bondAmount == 0) revert InvalidBondAmount();
        if (bondAmount > tranche.availableSupply) revert InsufficientBondsAvailable();
        
        uint256 cost = bondAmount * tranche.faceValue;
        
        processBondPurchase(bondAmount, cost, true, trancheId);
    }
    
    /// @notice Claim accumulated coupon payments
    /// @dev Calculates claimable amount and transfers payment tokens to the investor
    function claimCoupon() external nonReentrant whenNotPaused {
        if (balanceOf(msg.sender) == 0) revert NoCouponAvailable();
        
        if (lastCouponClaimDate[msg.sender] == 0) revert NoCouponAvailable();
        
        uint256 claimableAmount = calculateClaimableCoupon(msg.sender);
        if (claimableAmount == 0) revert NoCouponAvailable();
        
        processCouponClaim(claimableAmount, msg.sender, false, 0);
    }
    
    /// @notice Claim coupon for a specific tranche
    /// @param trancheId ID of the tranche
    function claimTrancheCoupon(uint256 trancheId) external nonReentrant whenNotPaused {
        if (trancheId >= trancheCount) revert TrancheDoesNotExist();
        Tranche storage tranche = tranches[trancheId];
        
        if (tranche.holdings[msg.sender] == 0) revert NoCouponAvailable();
        
        if (tranche.lastCouponClaimDate[msg.sender] == 0) revert NoCouponAvailable();
        
        uint256 claimableAmount = calculateTrancheCoupon(trancheId, msg.sender);
        if (claimableAmount == 0) revert NoCouponAvailable();
        
        processCouponClaim(claimableAmount, msg.sender, true, trancheId);
    }
    
    /// @notice Redeem bonds at maturity
    /// @dev Transfers principal and any outstanding coupon payments to the investor
    function redeemBonds() external nonReentrant whenNotPaused {
        if (!isBondMatured()) revert BondNotMatured();
        
        uint256 bondAmount = balanceOf(msg.sender);
        if (bondAmount == 0) revert NoBondsToRedeem();
        
        // Calculate claimable coupon
        uint256 claimableAmount = calculateClaimableCoupon(msg.sender);
        
        processBondRedemption(
            bondAmount,
            faceValue,
            claimableAmount,
            msg.sender,
            false,  // Not a tranche
            0,      // Tranche ID (not used)
            false,  // Not early redemption
            0       // No penalty
        );
    }
    
    /// @notice Redeem bonds from a specific tranche
    /// @param trancheId ID of the tranche
    function redeemTrancheBonds(uint256 trancheId) external nonReentrant whenNotPaused {
        if (trancheId >= trancheCount) revert TrancheDoesNotExist();
        Tranche storage tranche = tranches[trancheId];
        
        if (!isBondMatured()) revert BondNotMatured();
        
        uint256 bondAmount = tranche.holdings[msg.sender];
        if (bondAmount == 0) revert NoBondsToRedeem();
        
        // Calculate claimable coupon
        uint256 claimableAmount = calculateTrancheCoupon(trancheId, msg.sender);
        
        processBondRedemption(
            bondAmount,
            tranche.faceValue,
            claimableAmount,
            msg.sender,
            true,       // Is a tranche
            trancheId,  // Tranche ID
            false,      // Not early redemption
            0           // No penalty
        );
    }
    
    /// @notice Redeem bonds early with a penalty
    /// @param bondAmount Amount of bonds to redeem early
    /// @dev Calculates penalty and transfers reduced amount to investor
    function redeemBondsEarly(uint256 bondAmount) external nonReentrant whenNotPaused {
        if (!earlyRedemptionEnabled) revert EarlyRedemptionNotEnabled();
        if (bondAmount == 0 || bondAmount > balanceOf(msg.sender)) revert InvalidBondAmount();
        
        uint256 redemptionValue = bondAmount * faceValue;
        uint256 penalty = redemptionValue * earlyRedemptionPenaltyBps / 10000;
        
        // Calculate prorated coupon
        uint256 proRatedCoupon = calculateClaimableCoupon(msg.sender);
        
        processBondRedemption(
            bondAmount,
            faceValue,
            proRatedCoupon,
            msg.sender,
            false,      // Not a tranche
            0,          // Tranche ID (not used)
            true,       // Is early redemption
            penalty     // Penalty amount
        );
    }
    
    /// @notice Transfer bonds within a tranche to another address
    /// @param trancheId ID of the tranche
    /// @param to Recipient address
    /// @param amount Amount of bonds to transfer
    function transferTrancheBonds(uint256 trancheId, address to, uint256 amount) external nonReentrant whenNotPaused {
        if (trancheId >= trancheCount) revert TrancheDoesNotExist();
        if (to == address(0)) revert InvalidValue();
        if (amount == 0) revert InvalidValue();
        
        Tranche storage tranche = tranches[trancheId];
        
        if (amount > tranche.holdings[msg.sender]) revert InsufficientBonds();
        
        // Update state 
        tranche.holdings[msg.sender] -= amount;
        tranche.holdings[to] += amount;
        
        // Update coupon claim date for receiver
        if (tranche.lastCouponClaimDate[to] == 0) {
            tranche.lastCouponClaimDate[to] = block.timestamp;
        }
        
        emit TrancheTransfer(trancheId, msg.sender, to, amount);
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
    ) external onlyRole(ISSUER_ROLE) whenNotPaused nonReentrant {
        // Validation checks
        if (bytes(_name).length == 0) revert EmptyString();
        if (_faceValue == 0) revert InvalidValue();
        if (_couponRate > maxCouponRate) revert RateExceedsMaximum();
        if (_totalSupply == 0) revert InvalidValue();
        
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
    ) external onlyRole(ISSUER_ROLE) whenNotPaused nonReentrant {
        if (metricNames.length != metricValues.length) revert ArrayLengthMismatch();
        if (bytes(reportURI).length == 0) revert EmptyString();
        if (bytes(reportHash).length == 0) revert EmptyString();
        if (challengePeriod == 0) revert InvalidValue();
        if (requiredVerifications == 0) revert InvalidValue();
        
        uint256 reportId = impactReportCount++;
        ImpactReport storage newReport = impactReports[reportId];
        
        newReport.reportURI = reportURI;
        newReport.reportHash = reportHash;
        newReport.timestamp = block.timestamp;
        newReport.impactMetricsJson = impactMetricsJson;
        newReport.challengePeriodEnd = block.timestamp + challengePeriod;
        newReport.requiredVerifications = requiredVerifications;
        newReport.finalized = false;
        
        // Store quantitative metrics
        for (uint256 i = 0; i < metricNames.length; i++) {
            if (bytes(metricNames[i]).length == 0) revert EmptyString();
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
        
        ImpactReport storage report = impactReports[reportId];

        address sender = msg.sender;
        
        if (report.finalized) revert ReportAlreadyVerified();
        if (block.timestamp > report.challengePeriodEnd) revert ChallengePeriodEnded();
        if (report.hasVerified[sender]) revert AlreadyVoted();
        
        // Track this verifier
        report.hasVerified[sender] = true;
        report.verifiers.push(sender);
        
        uint256 verificationCount = report.verificationCount;
        unchecked {
            report.verificationCount = verificationCount + 1;
        }
        
        emit ImpactReportVerified(reportId, sender);
        
        // Check if report has reached required verifications
        if (verificationCount + 1 >= report.requiredVerifications) {
            report.finalized = true;
            emit ImpactReportFinalized(reportId);
            
            // Update green premium based on impact metrics
            uint256 currentGreenPremium = greenPremiumRate;
            uint256 currentBase = baseCouponRate;
            
            if (currentGreenPremium < (maxCouponRate - currentBase)) {
                uint256 oldCouponRate = couponRate;
                uint256 oldGreenPremiumRate = currentGreenPremium;
                
                uint256 newGreenPremium;
                unchecked {
                    newGreenPremium = currentGreenPremium + 50; // Increase by 0.5%
                }
                
                greenPremiumRate = newGreenPremium;
                couponRate = currentBase + newGreenPremium;
                
                emit CouponRateUpdated(couponRate);
                emit GreenPremiumRateUpdated(oldGreenPremiumRate, newGreenPremium);
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
       
        ImpactReport storage report = impactReports[reportId];
        
        address sender = msg.sender;
        
        if (report.finalized) revert ReportAlreadyVerified();
        if (block.timestamp > report.challengePeriodEnd) revert ChallengePeriodEnded();
        
        // Extend challenge period
        uint256 newChallengeEnd = block.timestamp + 7 days;
        report.challengePeriodEnd = newChallengeEnd;
        
        // Reset verification count
        report.verificationCount = 0;
        
        // Reset all verifications
        for (uint256 i = 0; i < report.verifiers.length; i++) {
            report.hasVerified[report.verifiers[i]] = false;
        }
        
        // Clear the verifiers array
        delete report.verifiers;
        
        emit ChallengePeriodExtended(reportId, newChallengeEnd);
        emit VerificationRequirementsReset(reportId);
        emit ImpactReportChallenged(reportId, sender, reason);
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
        if (votingPower == 0) revert NoVotingPower();
        
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
        if (proposal.forVotes <= proposal.againstVotes) revert ProposalRejected();
        
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
        if (newCouponPeriod == 0) revert InvalidValue();
        
        bytes32 operationId = keccak256(abi.encodePacked("updateCouponPeriod", newCouponPeriod, block.timestamp));
        
        if (checkAndScheduleOperation(operationId)) {
            uint256 oldCouponPeriod = couponPeriod;
            couponPeriod = newCouponPeriod;
            
            emit BondParametersUpdated(couponRate, couponRate, oldCouponPeriod, couponPeriod);
            emit OperationExecuted(operationId);
        }
    }
    
    /// @notice Set early redemption parameters
    /// @param enabled Whether early redemption is enabled
    /// @param penaltyBps Penalty in basis points for early redemption
    /// @dev Only callable by issuer
    function setEarlyRedemptionParams(bool enabled, uint256 penaltyBps) 
        external 
        onlyRole(ISSUER_ROLE) 
        whenNotPaused 
    {
        if (penaltyBps > 5000) revert InvalidValue(); // Maximum 50% penalty
        
        uint256 oldPenaltyBps = earlyRedemptionPenaltyBps;
        earlyRedemptionEnabled = enabled;
        earlyRedemptionPenaltyBps = penaltyBps;
        
        emit EarlyRedemptionStatusChanged(enabled);
        emit EarlyRedemptionPenaltyUpdated(oldPenaltyBps, penaltyBps);
    }
    
    /// @notice Emergency recovery function that can be called even when paused
    /// @param recoveryAddress Address to receive tokens
    /// @param amount Amount to recover
    /// @dev Only callable by admin
    function emergencyRecovery(address recoveryAddress, uint256 amount) 
        external 
        nonReentrant 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        if (recoveryAddress == address(0)) revert InvalidValue();
        if (amount == 0) revert InvalidRecoveryAmount();
        
        bytes32 operationId = keccak256(abi.encodePacked("emergencyRecovery", recoveryAddress, amount, block.timestamp));
        
        if (checkAndScheduleOperation(operationId)) {
            uint256 transferAmount = safeTransferTokens(recoveryAddress, amount);
            emit EmergencyRecovery(recoveryAddress, transferAmount);
            emit OperationExecuted(operationId);
        }
    }
    
    /// @notice Withdraw funds from project treasury
    /// @param recipient Address to receive the funds
    /// @param amount Amount to withdraw
    /// @param category Project category (e.g., "Solar Equipment", "Installation", "Permits")
    /// @param description Detailed description of the expense
    /// @dev Only callable by treasury role. All withdrawals are logged for transparency.
    function withdrawProjectFunds(
        address recipient, 
        uint256 amount, 
        string memory category,
        string memory description
    ) external onlyRole(TREASURY_ROLE) nonReentrant whenNotPaused {
        if (recipient == address(0)) revert InvalidValue();
        if (amount == 0) revert InvalidValue();
        if (bytes(category).length == 0) revert EmptyString();
        if (bytes(description).length == 0) revert EmptyString();
        if (amount > treasury.projectFunds) revert InsufficientFunds();
        
        updateTreasury(
            0,              // Principal reserve (no change)
            0,              // Coupon reserve (no change)
            -int256(amount), // Deduct from project funds
            0               // Emergency reserve (no change)
        );
        
        // Transfer funds
        safeTransferTokens(recipient, amount);
        
        emit FundWithdrawal(recipient, amount, category, description, block.timestamp);
    }
    
    /// @notice Emergency withdraw function for issuer (time-locked)
    /// @param amount Amount to withdraw
    /// @dev Protected by timelock
    function issuerEmergencyWithdraw(uint256 amount) 
        external 
        onlyRole(ISSUER_ROLE) 
        nonReentrant 
    {
        if (amount == 0) revert InvalidValue();
        
        bytes32 operationId = keccak256(abi.encodePacked("emergencyWithdraw", amount, block.timestamp));
        
        if (checkAndScheduleOperation(operationId)) {
            if (amount > treasury.emergencyReserve) revert InsufficientFunds();
            
            updateTreasury(
                0,               // Principal reserve (no change)
                0,               // Coupon reserve (no change)
                0,               // Project funds (no change)
                -int256(amount)  // Deduct from emergency reserve
            );
            
            safeTransferTokens(msg.sender, amount);
            
            emit FundWithdrawal(msg.sender, amount, "Emergency Withdrawal", block.timestamp);
            emit OperationExecuted(operationId);
        }
    }
    
    /// @notice Get the treasury status
    /// @return principalReserveResult Amount reserved for principal repayment
    /// @return couponReserveResult Amount reserved for coupon payments
    /// @return projectFundsResult Funds available for green projects
    /// @return emergencyReserveResult Emergency reserve funds
    /// @return totalBalanceResult Total balance of payment tokens in the contract
    function getTreasuryStatus() external view returns (
        uint256 principalReserveResult,
        uint256 couponReserveResult,
        uint256 projectFundsResult,
        uint256 emergencyReserveResult,
        uint256 totalBalanceResult
    ) {
        return (
            treasury.principalReserve,
            treasury.couponReserve,
            treasury.projectFunds,
            treasury.emergencyReserve,
            paymentToken.balanceOf(address(this))
        );
    }
    
    /// @notice Get the number of impact reports
    /// @return uint256 Total count of impact reports
    function getImpactReportCount() external view returns (uint256) {
        return impactReportCount;
    }

    /// @notice Get all addresses that have verified a specific impact report
    /// @param reportId ID of the report to query
    /// @return address[] Array of all verifier addresses that have participated in verification
    /// @dev This function returns the current list of verifiers who have verified the report
    /// @dev The list is reset when a report is successfully challenged
    /// @dev Throws ReportDoesNotExist if the report ID is invalid
    function getReportVerifiers(uint256 reportId) external view returns (address[] memory) {
        if (reportId >= impactReportCount) revert ReportDoesNotExist();
        return impactReports[reportId].verifiers;
    }
    
    /// @notice Get the number of green certifications
    /// @return uint256 Total count of green certifications
    function getGreenCertificationCount() external view returns (uint256) {
        return greenCertifications.length;
    }
    
    /// @notice Get tranche details
    /// @param trancheId ID of the tranche
    /// @return trancheName Tranche name
    /// @return trancheFaceValue Face value of tranche bonds
    /// @return trancheCouponRate Coupon rate for tranche
    /// @return trancheSeniority Seniority level (lower is more senior)
    /// @return trancheTotalSupply Total supply of tranche
    /// @return trancheAvailableSupply Available supply of tranche
    function getTrancheDetails(uint256 trancheId) external view returns (
        string memory trancheName,
        uint256 trancheFaceValue,
        uint256 trancheCouponRate,
        uint256 trancheSeniority,
        uint256 trancheTotalSupply,
        uint256 trancheAvailableSupply
    ) {
        if (trancheId >= trancheCount) revert TrancheDoesNotExist();
        Tranche storage tranche = tranches[trancheId];
        
        return (
            tranche.name,
            tranche.faceValue,
            tranche.couponRate,
            tranche.seniority,
            tranche.totalSupply,
            tranche.availableSupply
        );
    }
    
    /// @notice Get tranche holdings for an address
    /// @param trancheId ID of the tranche
    /// @param holder Address of the holder
    /// @return uint256 Bond holdings in the tranche
    function getTrancheHoldings(uint256 trancheId, address holder) external view returns (uint256) {
        if (trancheId >= trancheCount) revert TrancheDoesNotExist();
        return tranches[trancheId].holdings[holder];
    }
    
    /// @notice Get bond status
    /// @return bondNameResult Name of the bond
    /// @return bondSymbolResult Symbol of the bond
    /// @return faceValueResult Face value of each bond
    /// @return bondTotalSupplyResult Total supply of bonds
    /// @return availableSupplyResult Available supply of bonds
    /// @return baseCouponRateResult Base coupon rate
    /// @return greenPremiumRateResult Green premium rate
    /// @return couponRateResult Current coupon rate
    /// @return maturityDateResult Maturity date of the bond
    /// @return issuanceDateResult Issuance date of the bond
    /// @return earlyRedemptionEnabledResult Whether early redemption is enabled
    /// @return earlyRedemptionPenaltyBpsResult Early redemption penalty in basis points
    function getBondStatus() external view returns (
        string memory bondNameResult,
        string memory bondSymbolResult,
        uint256 faceValueResult,
        uint256 bondTotalSupplyResult,
        uint256 availableSupplyResult,
        uint256 baseCouponRateResult,
        uint256 greenPremiumRateResult,
        uint256 couponRateResult,
        uint256 maturityDateResult,
        uint256 issuanceDateResult,
        bool earlyRedemptionEnabledResult,
        uint256 earlyRedemptionPenaltyBpsResult
    ) {
        return (
            bondName,
            bondSymbol,
            faceValue,
            bondTotalSupply,
            availableSupply,
            baseCouponRate,
            greenPremiumRate,
            couponRate,
            maturityDate,
            issuanceDate,
            earlyRedemptionEnabled,
            earlyRedemptionPenaltyBps
        );
    }

    /// @notice Get current allocation percentages
    /// @return principalPercentage Percentage for principal reserve in basis points
    /// @return projectPercentage Percentage for project funds in basis points
    /// @return emergencyPercentage Percentage for emergency reserve in basis points
    function getAllocationPercentages() external view returns (
        uint256 principalPercentage,
        uint256 projectPercentage,
        uint256 emergencyPercentage
    ) {
        return (principalAllocationBps, projectAllocationBps, emergencyAllocationBps);
    }
    
    /// @notice Override of ERC20 transfer to handle coupon claim dates
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @return bool Success
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        // Update coupon claim date for receiver if they don't have one
        if (lastCouponClaimDate[to] == 0 && amount > 0) {
            lastCouponClaimDate[to] = block.timestamp;
        }
        
        return super.transfer(to, amount);
    }
    
    /// @notice Override of ERC20 transferFrom to handle coupon claim dates
    /// @param from Sender address
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @return bool Success
    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        // Update coupon claim date for receiver if they don't have one
        if (lastCouponClaimDate[to] == 0 && amount > 0) {
            lastCouponClaimDate[to] = block.timestamp;
        }
        
        return super.transferFrom(from, to, amount);
    }
    
    /// @notice Get governance parameters
    /// @return quorumResult Current quorum requirement
    /// @return votingPeriodResult Current voting period
    /// @return proposalCountResult Total proposal count
    function getGovernanceParams() external view returns (
        uint256 quorumResult,
        uint256 votingPeriodResult,
        uint256 proposalCountResult
    ) {
        return (quorum, votingPeriod, proposalCount);
    }
    
    /// @notice Update governance parameters
    /// @param newQuorum New quorum value
    /// @param newVotingPeriod New voting period
    /// @dev Only callable by admin with timelock
    function updateGovernanceParams(uint256 newQuorum, uint256 newVotingPeriod) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused 
    {
        if (newQuorum == 0) revert InvalidValue();
        if (newVotingPeriod == 0) revert InvalidValue();
        
        bytes32 operationId = keccak256(abi.encodePacked("updateGovernance", newQuorum, newVotingPeriod, block.timestamp));
        
        if (checkAndScheduleOperation(operationId)) {
            uint256 oldQuorum = quorum;
            uint256 oldVotingPeriod = votingPeriod;
            
            // Update storage
            quorum = newQuorum;
            votingPeriod = newVotingPeriod;
            
            emit GovernanceParamsUpdated(oldQuorum, newQuorum, oldVotingPeriod, newVotingPeriod);
            emit OperationExecuted(operationId);
        }
    }
    
    /// @notice Version number for this contract implementation
    /// @return string Version identifier
    function version() external pure returns (string memory) {
        return "v1.0.0";
    }
}