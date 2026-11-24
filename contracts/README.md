# AgentPredict — contracts

Foundry project for the AgentPredict game contract (Solidity ^0.8.28,
OpenZeppelin Contracts v5.7.0 for `Ownable` + `Pausable`).

## Layout

- `src/AgentPredict.sol` — the game contract. No token, no stakes, no fees.
- `test/AgentPredict.t.sol` — 22 unit tests with mock registry + mock feed.
- `test/AgentPredictFork.t.sol` — 3 fork tests against the real BSC contracts.
- `script/Deploy.s.sol` — deployment script (BSC mainnet, chain id 56).

## Build / test

```bash
forge build
forge test                 # 25 tests (22 unit + 3 fork), all passing
forge test --gas-report    # gas table
```

Fork tests need network access to `https://bsc.publicnode.com`
(configured in `foundry.toml` under `[rpc_endpoints]`).

## Deploy (do NOT run without the user's go-ahead)

```bash
forge script script/Deploy.s.sol --rpc-url bsc --broadcast
```

Then verify the source on BscScan (and Sourcify) so the code is public
and open-source, as the hackathon rules require:

```bash
forge verify-contract <DEPLOYED_ADDRESS> src/AgentPredict.sol:AgentPredict \
  --chain 56 --etherscan-api-key <BSCSCAN_API_KEY> \
  --constructor-args $(cast abi-encode "constructor(address,address)" \
    0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F \
    0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf)
```

Constructor arguments (fixed, verified on-chain 2026-11-19):

| Argument | Address | Verified as |
|---|---|---|
| Agent ID registry | `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` | `balanceOf(user wallet) = 1`; `name()`/`symbol()`/`totalSupply()`/`supportsInterface()` all revert — the contract only ever calls `balanceOf` |
| Chainlink BTC/USD feed | `0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf` | description `BTC / USD`, 8 decimals, ~60s heartbeat; live price $63,535.29 at check time |

## Gas (measured with `forge test --gas-report`, 2026-11-19)

| Action | Gas |
|---|---|
| Deployment | 2,105,617 (contract size 10,926 bytes) |
| `vote()` | avg ~216,500, max ~303,000 in the test suite (first vote of a new day by a first-time voter is the most expensive path: round rollover + voter indexing) |
| `settle()` | ~24,000–76,000 (avg ~46,000) |
| `pause()` / `unpause()` | ~24,000–28,000 |

At a 1 gwei gas price, deployment costs ~0.0021 BNB and a worst-case vote
~0.0003 BNB. Check the live BSC gas price at deploy time; the deployer's
wallet must hold enough BNB (the user's wallet held only 0.00011476 BNB on
2026-11-19 — likely NOT enough at 1 gwei).

## Static analysis

```bash
export PATH="$HOME/.foundry/bin:$PATH"
slither src/AgentPredict.sol --exclude-dependencies
```

Result 2026-11-19: 7 findings, all informational, no High/Medium:
- `timestamp` (block.timestamp for day boundaries + feed staleness) —
  intentional; the game is defined by UTC days.
- `unused-return` (`latestRoundData` fields we deliberately ignore) —
  intentional; only `answer` and `updatedAt` are needed.
- `solc-version` — addressed by pinning `pragma solidity ^0.8.28`
  (built with solc 0.8.30).
