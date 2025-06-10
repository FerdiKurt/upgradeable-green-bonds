# Upgradeable Green Bonds Smart Contract

An upgradeable smart contract system for issuing and managing green bonds to support climate and environmental projects. Built with OpenZeppelin's upgradeable contracts pattern and featuring DeFi functionality including tranches, governance, and impact reporting.

## 🌱 Overview

The Upgradeable Green Bonds contract enables organizations to issue tokenized green bonds that fund environmental projects while providing transparent impact reporting and dynamic interest rates based on environmental performance.

### Key Features

- **Upgradeable Architecture**: Built with OpenZeppelin's UUPS proxy pattern
- **Dynamic Coupon Rates**: Interest rates that increase based on verified environmental impact
- **Multi-Tranche Support**: Different risk/reward profiles for various investor types
- **On-Chain Governance**: Decentralized decision-making with timelock protection
- **Impact Reporting**: Verified environmental metrics with challenge mechanisms
- **Security**: Role-based access control, reentrancy protection, and pausable functionality
- **Early Redemption**: Optional early bond redemption with configurable penalties
- **reasury Management**: Automated fund allocation and transparent project funding

## 📋 Table of Contents

- [Architecture](#architecture)
- [Installation](#installation)
- [Deployment](#deployment)
- [Usage](#usage)
- [Contract Functions](#contract-functions)
- [Security Features](#security-features)
- [Testing](#testing)
- [Governance](#governance)
- [Impact Reporting](#impact-reporting)
- [Contributing](#contributing)
- [License](#license)

## 🏗️ Architecture

### Core Components

1. **Bond Management**: ERC20-based bond tokens with face value and maturity
2. **Treasury System**: Multi-reserve fund management (principal, coupon, project, emergency)
3. **Tranche System**: Multiple bond classes with different seniority levels
4. **Impact Verification**: Multi-verifier system for environmental impact validation
5. **Governance Module**: On-chain voting with timelock protection
6. **Upgradeability**: UUPS proxy pattern for future improvements

### Contract Hierarchy

```
UpgradeableGreenBonds
├── Initializable (OpenZeppelin)
├── AccessControlUpgradeable (OpenZeppelin)
├── ReentrancyGuardUpgradeable (OpenZeppelin)
├── PausableUpgradeable (OpenZeppelin)
├── ERC20Upgradeable (OpenZeppelin)
└── UUPSUpgradeable (OpenZeppelin)
```

### Roles

- **DEFAULT_ADMIN_ROLE**: Contract administration and role management
- **ISSUER_ROLE**: Bond issuance and parameter updates
- **VERIFIER_ROLE**: Impact report verification
- **TREASURY_ROLE**: Fund management and withdrawals
- **UPGRADER_ROLE**: Contract upgrade authorization

## 🚀 Installation

### Prerequisites

- [Foundry](https://getfoundry.sh/) for development and testing
- [Git](https://git-scm.com/) for version control
- [Node.js](https://nodejs.org/) (optional, for additional tooling)

### Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-org/green-bonds-contract.git
   cd green-bonds-contract
   ```

2. **Install dependencies**
   ```bash
   forge install
   ```

3. **Build the contract**
   ```bash
   forge build
   ```

4. **Run tests**
   ```bash
   forge test
   ```

## 📦 Deployment

### Local Development

1. **Start local blockchain**
   ```bash
   anvil
   ```

2. **Deploy to local network**
   ```bash
   forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
   ```

### Testnet Deployment

1. **Set environment variables**
   ```bash
   export PRIVATE_KEY=your_private_key
   export RPC_URL=your_testnet_rpc_url
   export ETHERSCAN_API_KEY=your_etherscan_api_key
   ```

2. **Deploy and verify**
   ```bash
   forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
   ```

### Mainnet Deployment

⚠️ **Important**: Thoroughly test on testnets before mainnet deployment.

```bash
forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify --slow
```

## 💼 Usage

### Basic Bond Operations

#### Purchase Bonds
```solidity
// Approve payment tokens first
paymentToken.approve(greenBondsAddress, amount);

// Purchase bonds
greenBonds.purchaseBonds(bondAmount);
```

#### Claim Coupons
```solidity
// Calculate claimable amount
uint256 claimable = greenBonds.calculateClaimableCoupon(investor);

// Claim coupon payment
greenBonds.claimCoupon();
```

#### Redeem at Maturity
```solidity
// Redeem bonds for principal + final coupon
greenBonds.redeemBonds();
```

### Tranche Operations

#### Purchase Tranche Bonds
```solidity
// Purchase from specific tranche
greenBonds.purchaseTrancheBonds(trancheId, bondAmount);

// Transfer tranche bonds
greenBonds.transferTrancheBonds(trancheId, recipient, amount);
```

### Administrative Functions

#### Add Impact Report
```solidity
string[] memory metricNames = ["co2_reduction", "energy_generated"];
uint256[] memory metricValues = [1000, 5000];

greenBonds.addImpactReport(
    "https://example.com/report",
    "report_hash",
    "detailed_metrics_json",
    metricNames,
    metricValues,
    7 days,  // challenge period
    2        // required verifications
);
```

#### Verify Impact Report
```solidity
greenBonds.verifyImpactReport(reportId);
```

## 🔧 Contract Functions

### Core Bond Functions

| Function | Description | Access |
|----------|-------------|---------|
| `purchaseBonds(uint256)` | Purchase bonds with payment tokens | Public |
| `claimCoupon()` | Claim accumulated coupon payments | Public |
| `redeemBonds()` | Redeem bonds at maturity | Public |
| `redeemBondsEarly(uint256)` | Early redemption with penalty | Public |
| `calculateClaimableCoupon(address)` | View claimable coupon amount | View |

### Tranche Functions

| Function | Description | Access |
|----------|-------------|---------|
| `addTranche(...)` | Create new bond tranche | ISSUER_ROLE |
| `purchaseTrancheBonds(uint256, uint256)` | Purchase from specific tranche | Public |
| `transferTrancheBonds(uint256, address, uint256)` | Transfer tranche bonds | Public |
| `redeemTrancheBonds(uint256)` | Redeem tranche bonds | Public |

### Impact Reporting

| Function | Description | Access |
|----------|-------------|---------|
| `addImpactReport(...)` | Add new impact report | ISSUER_ROLE |
| `verifyImpactReport(uint256)` | Verify impact report | VERIFIER_ROLE |
| `challengeImpactReport(uint256, string)` | Challenge report validity | VERIFIER_ROLE |

### Governance

| Function | Description | Access |
|----------|-------------|---------|
| `createProposal(...)` | Create governance proposal | ISSUER_ROLE |
| `castVote(uint256, bool)` | Vote on proposal | Public |
| `executeProposal(uint256)` | Execute passed proposal | Public |

### Treasury Management

| Function | Description | Access |
|----------|-------------|---------|
| `withdrawProjectFunds(...)` | Withdraw project funding | TREASURY_ROLE |
| `issuerEmergencyWithdraw(uint256)` | Emergency fund withdrawal | ISSUER_ROLE |
| `emergencyRecovery(address, uint256)` | Emergency token recovery | DEFAULT_ADMIN_ROLE |

