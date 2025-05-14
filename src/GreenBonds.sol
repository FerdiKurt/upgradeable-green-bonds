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
    
