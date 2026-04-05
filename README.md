# pliq-bc

Solidity smart contracts for the Pliq on-chain rental system. Built with Foundry and deployed to World Chain / Base Sepolia.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)

## Setup

```bash
cd pliq-bc
forge install
cp .env.example .env
# Edit .env with your keys
```

## Contracts

| Contract | Description |
|----------|-------------|
| `PliqRegistry` | User registration with World ID verification, listing creation, and rental applications |
| `RentalAgreement` | Rental lifecycle management: deposits, rent payments, move-in/out, escrow release |
| `StakingManager` | Economic stakes for listings, visits, and rentals with slashing mechanics |
| `ReputationAccumulator` | Soulbound ERC-5192 reputation tokens with score decay and Merkle proofs |
| `PaymentRouter` | Fee routing, recurring payments, and CCTP cross-chain bridging |
| `DisputeResolver` | Dispute lifecycle: evidence submission, juror voting, resolution, and appeals |

Supporting libraries:

| Path | Description |
|------|-------------|
| `src/interfaces/` | Contract interfaces (`IPliqRegistry`, `IRentalAgreement`, etc.) |
| `src/libraries/PliqTypes.sol` | Shared type definitions (enums, structs) |
| `src/libraries/PliqErrors.sol` | Custom error definitions |

Dependencies (in `lib/`):

- `forge-std` -- Foundry standard library
- `openzeppelin-contracts` -- OpenZeppelin contract library

## Configuration

Copy `.env.example` to `.env` and fill in the values:

| Variable | Required | Description |
|----------|----------|-------------|
| `PRIVATE_KEY` | Yes | Deployer wallet private key |
| `BASE_SEPOLIA_RPC_URL` | Yes | Base Sepolia RPC endpoint |
| `WORLD_CHAIN_RPC_URL` | Yes | World Chain RPC endpoint |
| `ETHERSCAN_API_KEY` | No | Block explorer API key for contract verification |
| `WORLD_ID_ROUTER_ADDRESS` | Yes | World ID router contract address |
| `WORLD_ID_ACTION_ID` | Yes | World ID action identifier |
| `TREASURY_ADDRESS` | Yes | Protocol treasury multisig address |
| `USDC_TOKEN_ADDRESS` | Yes | USDC token contract address |

## Build

```bash
forge build
```

## Test

```bash
forge test
forge test -vvvv                              # Verbose output
forge test --match-path test/PliqRegistry.t.sol  # Single contract
forge test --gas-report                       # Gas benchmarks
```

## Deploy

```bash
# Base Sepolia testnet
forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast

# World Chain
forge script script/Deploy.s.sol --rpc-url worldchain --broadcast

# Local Anvil
anvil
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

The deploy script (`script/Deploy.s.sol`) deploys all six contracts in dependency order, grants cross-contract roles, configures USDC as a supported token, and sets minimum stake amounts.

## Verify

```bash
forge verify-contract <ADDRESS> <CONTRACT> --rpc-url base_sepolia
```

## Development

```bash
forge build      # Compile contracts
forge test       # Run all tests
forge fmt        # Format Solidity code
forge snapshot   # Gas snapshot
forge coverage   # Coverage report
```

## Note on Foundry Configuration

The `foundry.toml` pins Solidity compiler to `0.8.28` with optimizer enabled (200 runs). Gas reports are configured for all six core contracts. RPC endpoints (`base_sepolia`, `worldchain`) are read from environment variables.
