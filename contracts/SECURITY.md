# AgentPredict — security notes

## Owner powers (deployer = owner)

The owner can do exactly two things, both documented here:

| Function | What it does | Why it exists |
|---|---|---|
| `pause()` | Stops `vote()` (emergency brake). | If the price feed is compromised or a bug is found, voting can be frozen while a fix is prepared. |
| `unpause()` | Resumes `vote()`. | Lifts the emergency brake. |

That is all. There is deliberately NO function to:

- mint, transfer, or hold funds (the contract **never receives or holds
  any BNB, token, or stake** — there is no `receive`/`fallback` payable
  path and no withdrawal function because there is nothing to withdraw);
- change the price feed or the Agent ID registry (both are `immutable`,
  set once in the constructor);
- change point values, round length, or the feed staleness guard
  (all are `constant`);
- edit, delete, or override any vote, round result, or leaderboard entry;
- pause `settle()` — settling already-earned points stays available even
  while voting is paused.

## Trust assumptions

- **Chainlink BTC/USD feed** (`0x264990fb…a5Ebf`): the contract trusts the
  feed's `latestRoundData` answer, guarded by `answer > 0` and
  `updatedAt` within 2 hours (heartbeat is ~60s). If Chainlink stops
  updating, voting reverts with `FeedStale` rather than resolving on a
  stale price. Resolution uses the price observed at rollover, not a
  time-weighted average — acceptable for a points-only game with no stakes.
- **Agent ID registry** (`0x60B92624…b022F`): the contract trusts
  `balanceOf` as proof of holding an Agent ID. Verified on-chain
  2026-11-19: the registry only implements `balanceOf` — `name()`,
  `symbol()`, `totalSupply()` and `supportsInterface()` all revert, so the
  contract never calls them.
- **Day boundaries** use `block.timestamp / 1 days` (UTC days). A validator
  can shift `block.timestamp` by seconds, which cannot change which UTC day
  a vote falls in except within seconds of midnight — immaterial for a
  points-only game.
- **Ties** (final price exactly equals the reference price) count as UP.
  Exact ties are extremely unlikely at 8-decimal precision.
- **First-vote reference**: a round's reference price is the feed price at
  the moment of the first vote of that UTC day, not the price at 00:00 UTC
  (there is no keeper transaction at midnight). This is disclosed in the
  UI and docs.

## What a voter approves

Exactly one thing: their own `vote(bool)` transaction, confirmed in their
own wallet. No approvals, no allowances, no signatures beyond that
transaction. The frontend never asks for a QR code, pairing code, seed
phrase, private key, or API secret — and the contract could not use them.

## Static analysis

Slither 0.11.6, 2026-11-19: 7 findings, all informational (see
`contracts/README.md`). No High or Medium findings.
