# AgentPredict

A daily Bitcoin direction prediction game for Agent ID holders, built for
the Binance Wallet + BNB Chain Agent ID Hackathon (60,000 USDC;
submission 2026-11-18 → 2026-12-09 08:00 UTC).

Each UTC day is one round: will BTC close the day above or below the
round's reference price? The reference is the Chainlink BTC/USD price at
the first vote of the day. Only Agent ID holders can vote — one vote per
address per round. Voting is free except gas: no stakes, no fees, no
token, no promised returns. Correct vote +10 points, wrong vote +1 point.
Streaks and a points leaderboard are on-chain. Rounds resolve lazily
(the first vote of a new day settles the previous day), so no keeper is
needed.

## Status (2026-11-19)

**Build complete, not deployed.** Contract + tests + frontend + docs are
done and verified. Deployment, hosting, and submission still need the
user's go-ahead (see "Deploy" below).

## Layout

```
contracts/   Foundry project: src/AgentPredict.sol, tests, deploy script
frontend/    Static site (plain HTML/JS + vendored ethers v6) — GitHub Pages ready
docs/        RESEARCH.md (what was verified), SUBMISSION.md (submission pack)
tools/       verify-feeds.mjs — live on-chain verification of registry + feed
```

## Run locally

```bash
# Contracts
cd contracts && forge build && forge test

# Frontend (needs the deployed contract address in app.js first)
cd frontend && python3 -m http.server 8931
# open http://localhost:8931
```

## Deploy (steps only — do NOT run without the user's go-ahead)

1. **Re-pair the wallet** — the Binance wallet session expired
   2026-11-07; run `baw auth signin`, approve in the Binance app, then
   `baw auth verify`. Sessions last only ~3–4.5 hours.
2. **Top up BNB** — deployment costs ~0.0021 BNB at 1 gwei gas price
   (check the live gas price first). The wallet held only 0.00011476 BNB
   on 2026-11-19 — likely not enough.
3. **Deploy + verify** (commands in `contracts/README.md`):
   `forge script script/Deploy.s.sol --rpc-url bsc --broadcast`, then
   `forge verify-contract` on BscScan (and Sourcify).
4. **Host the frontend** — deploy `frontend/` to GitHub Pages as-is,
   after setting the deployed contract address in `app.js` CONFIG.
5. **Submit** — fill in the website URL + contract address in
   `docs/SUBMISSION.md` and submit through the official channel
   (see the open item below).

## Known limitations

- **Submission form not found.** The official announcement says to
  submit "project name, website, contract address(es), Agent ID usage
  description, and other required materials" with "no registration
  needed", but gives no form URL or portal. Monitor the official
  announcement page, @BinanceWallet, and BNB Chain channels before the
  9 Dec 2026 15:00 WIB deadline. Never use a third-party form.
- **≥30 Agent ID interactors needed** for the Innovation Award. No
  outreach plan exists yet — this is the real bottleneck.
- **Reference price is set by the first vote of the day**, not by the
  00:00 UTC price (no keeper). Disclosed in the UI and docs.
- **Fork test caveat:** free BSC RPCs don't serve archive account state,
  so the resolution fork test patches only the feed's timestamp fields
  via `mockCall` while keeping the real on-chain price — documented in
  `test/AgentPredictFork.t.sol`.
- **First vote of a day is the most expensive** (~303k gas worst case)
  because it settles the previous round and opens the new one.
- **Ties count as UP.** Exact ties at 8-decimal precision are extremely
  unlikely.
- **No token, no sale, no "earn" language** anywhere — by design, and
  required by the hackathon rules.
