# pliq-bc

Solidity smart contracts for the Pliq rental platform. Built with Foundry and deployed to World Chain / Base.

## Prerequisites

- [Foundry](https://getfoundry.sh/) (forge, cast, anvil)

## Setup

```bash
# Clone and enter the repo
cd pliq-bc

# Install dependencies
forge install

# Copy environment config
cp .env.example .env
# Edit .env with your keys

# Build
forge build
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DEPLOYER_PRIVATE_KEY` | Yes | Deployer wallet private key |
| `WORLD_CHAIN_RPC_URL` | Yes | World Chain RPC endpoint |
| `BASE_SEPOLIA_RPC_URL` | No | Base Sepolia testnet RPC |
| `ETHERSCAN_API_KEY` | No | Etherscan API key for verification |
| `WORLDSCAN_API_KEY` | No | WorldScan API key for verification |

## Contracts

| Contract | Description |
|----------|-------------|
| `PliqRegistry` | User/property registration, role management (AccessControl) |
| `RentalAgreement` | Lease state machine: Draft -> Active -> Completed/Disputed |
| `StakingManager` | Listing, visit, rental staking with lock periods and slashing |
| `PaymentRouter` | USDC/EURC escrow: deposit, release, refund, dispute lock |
| `ReputationAccumulator` | SHA-3 Merkle tree root tracking for Proof-of-Rent |
| `DisputeResolver` | Dispute filing, evidence, resolution, fund distribution |

## Project Structure

```
src/
├── PliqRegistry.sol
├── RentalAgreement.sol
├── StakingManager.sol
├── ReputationAccumulator.sol
├── PaymentRouter.sol
└── DisputeResolver.sol
script/
└── Deploy.s.sol              # Deployment script
lib/
├── forge-std/                # Foundry standard library
└── openzeppelin-contracts/   # OpenZeppelin v5.6.1
```

## Development

```bash
# Build contracts
forge build

# Run tests
forge test

# Run tests with verbosity
forge test -vvvv

# Gas report
forge test --gas-report

# Coverage
forge coverage

# Format
forge fmt
```

## Deployment

```bash
# Deploy to Base Sepolia testnet
forge script script/Deploy.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast

# Deploy to World Chain
forge script script/Deploy.s.sol --rpc-url $WORLD_CHAIN_RPC_URL --broadcast

# Verify on Etherscan
forge verify-contract <address> src/PliqRegistry.sol:PliqRegistry --chain-id <chain_id>
```

## Local Testing with Anvil

```bash
# Start local node
anvil

# Deploy to local node
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```
