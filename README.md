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

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

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
