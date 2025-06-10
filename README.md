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


### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
