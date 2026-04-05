# pliq-bc

Solidity smart contracts for the Pliq privacy-preserving rental platform. Built with Foundry and deployed to World Chain / Base Sepolia.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)

## Setup

```bash
cd pliq-bc
forge install
cp .env.example .env
# Edit .env with your keys
```

## Compile

```bash
forge build
```

## Test

```bash
forge test
forge test --gas-report
forge test --match-path test/PliqRegistry.t.sol -vvvv
```

## Deploy

```bash
# Base Sepolia testnet
forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast

# World Chain mainnet
forge script script/Deploy.s.sol --rpc-url worldchain --broadcast
```

## Verify

```bash
forge verify-contract <ADDRESS> <CONTRACT> --rpc-url base_sepolia
```

## Contracts

| Contract | Description |
|----------|-------------|
| `PliqRegistry` | User registration with World ID, listing creation, rental applications |
| `RentalAgreement` | Rental lifecycle: deposits, rent payments, move-in/out, escrow release |
| `StakingManager` | Economic stakes for listings/visits/rentals with slashing |
| `ReputationAccumulator` | Soulbound ERC-5192 reputation tokens with score decay and Merkle proofs |
| `PaymentRouter` | Fee routing, recurring payments, CCTP cross-chain bridge |
| `DisputeResolver` | Dispute lifecycle: evidence, juror voting, resolution, appeals |

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `PRIVATE_KEY` | Yes | Deployer wallet private key |
| `BASE_SEPOLIA_RPC_URL` | Yes | Base Sepolia RPC endpoint |
| `WORLD_CHAIN_RPC_URL` | Yes | World Chain RPC endpoint |
| `ETHERSCAN_API_KEY` | No | Block explorer API key |
| `WORLD_ID_ROUTER_ADDRESS` | Yes | World ID router contract |
| `WORLD_ID_ACTION_ID` | Yes | World ID action identifier |
| `TREASURY_ADDRESS` | Yes | Protocol treasury address |
| `USDC_TOKEN_ADDRESS` | Yes | USDC token address |

## Project Structure

```
src/
├── PliqRegistry.sol
├── RentalAgreement.sol
├── StakingManager.sol
├── ReputationAccumulator.sol
├── PaymentRouter.sol
├── DisputeResolver.sol
├── interfaces/               # Contract interfaces (IPliqRegistry, etc.)
└── libraries/                # Shared types (PliqTypes) and errors (PliqErrors)
test/
├── PliqRegistry.t.sol
├── RentalAgreement.t.sol
├── StakingManager.t.sol
├── ReputationAccumulator.t.sol
├── PaymentRouter.t.sol
├── DisputeResolver.t.sol
├── Integration.t.sol         # Full lifecycle integration tests
└── helpers/                  # Mock contracts and test constants
script/
└── Deploy.s.sol              # Deployment script with role grants
lib/
├── forge-std/
└── openzeppelin-contracts/
```

## Development

```bash
forge build           # Compile
forge test            # Run tests
forge test -vvvv      # Verbose output
forge test --gas-report  # Gas benchmarks
forge coverage        # Coverage report
forge fmt             # Format code
```

## Local Testing with Anvil

```bash
anvil
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```
