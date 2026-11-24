# AgentPredict — submission pack

## Project

- **Name:** AgentPredict
- **One-line pitch:** A daily Bitcoin direction prediction game that only
  Agent ID holders can play — free to vote (gas only), points and streaks
  on-chain, settled by the Chainlink BTC/USD price feed.
- **Website:** _TODO — deploy `frontend/` to GitHub Pages and paste the URL here_
- **Contract:** _TODO — paste the deployed BSC address here after deployment_
- **Deployer / Agent ID:** `homsin.ai`
  (wallet `0xbb1777a4ab27cd1b871371add8eceb645e69354a`)
- **Reward receiving address:** _TODO — fill in at submission time_

## What it does

Each UTC day is one round. The question: will BTC close the day above or
below the round's reference price? The reference price is the Chainlink
BTC/USD price at the first vote of the day. Only Agent ID holders can
vote (the contract checks `balanceOf` on the Agent ID registry). One vote
per address per round. Voting is free except gas — no stakes, no fees, no
token, no promised returns. Correct vote +10 points, wrong vote +1 point.
Streaks (consecutive days voted) and a points leaderboard are on-chain.
Rounds resolve lazily: the first vote of a new day settles the previous
day against the current Chainlink price, so no keeper is needed.

## Agent ID usage

Agent ID is the core access control, not a decoration: `vote()` reverts
with `NotAgentIdHolder` unless the caller's address holds an Agent ID
(`balanceOf > 0` on `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`). Every
interaction — votes, points, streaks, leaderboard — is keyed to the
Agent ID holder's address. The frontend shows a clear message to
non-holders explaining that an Agent ID is required and that one can be
claimed free in the Binance app (Wallet → homepage banner → Agent ID).
Agent ID is never used to look up other people's wallets by name.

## How to verify

- **Contract source:** verified open-source on BscScan after deployment
  (see `contracts/README.md` for the exact `forge verify-contract`
  command) and on Sourcify.
- **Agent ID gate:** call `balanceOf(<any address>)` on
  `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`; vote from an address with
  balance 0 reverts (proven by fork test `testFork_RealRegistryGate`).
- **Price feed:** the contract reads Chainlink BTC/USD on BSC,
  `0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf` (description "BTC / USD",
  8 decimals, ~60s heartbeat; verified live 2026-11-19).
- **Tests:** 25/25 pass (`forge test`): 22 unit tests + 3 fork tests
  against the real registry and feed. Gas: deploy 2,105,617; vote avg
  ~216,500 / max ~303,000. Slither 0.11.6: 7 informational findings only.
- **Frontend:** static site in `frontend/` (plain HTML/JS + ethers v6
  vendored locally); no build step; no server; no QR/pairing login.

## Judging-criteria mapping

| Criterion (weight) | How AgentPredict meets it |
|---|---|
| Agent ID Application Depth (30%) | Agent ID gates the entire core flow: only holders can vote, and every vote, point, streak, and leaderboard row belongs to a holder's address. The game cannot function without Agent ID. |
| Practicality & Feasibility (25%) | A real, daily habit for Agent ID holders (one tap a day, gas-only); no token economics to bootstrap, no keeper, no oracle of our own — Chainlink does the pricing. |
| Product Completion (25%) | Contract + full test suite + static frontend are built and verified; deploy + host + submit remain (see open items). |
| Innovation (20%) | Prediction markets are a proven format, but AgentPredict is the first Agent-ID-gated daily prediction game in this hackathon's field (competitors seen: check-in wall, arena shooter, specimen lab). |

## Red-line compliance checklist

- [x] **No web QR-code login:** frontend uses the injected provider
  (`window.ethereum`) only. No QR codes, no pairing codes, no session
  storage on any server.
- [x] **No bypass of user transaction confirmation:** the only
  state-changing call is the user's own `vote()` (and optional manual
  `settle()`), confirmed in their own wallet. No prompts or flows that
  skip confirmation.
- [x] **No unauthorized asset transfers:** the contract holds no funds
  and has no payable path; votes transfer nothing.
- [x] **Contracts open-source with disclosed owner permissions:**
  source verified on BscScan/Sourcify; owner powers are pause/unpause
  only — documented in `contracts/SECURITY.md`. No minting, no fund
  custody, no pausing of withdrawals (there are no funds to withdraw).
- [x] **No brand impersonation:** the project, token (there is none),
  and domain names do not use "Binance" or "BNB". The UI factually
  states the game runs on BNB Chain and is a hackathon project, and
  carries an explicit "Not affiliated with Binance or BNB Chain"
  disclaimer; the wallet instructions name the Binance Wallet app
  because that is where Agent IDs are claimed. None of this presents
  the project as an official Binance product.
- [x] **No credential collection:** the frontend never asks for seed
  phrases, private keys, API secrets, or pairing codes.
- [x] **No promised returns:** no token, no sale, no "earn"/"passive
  income" language anywhere in code, UI, or docs. Points only.
- [x] **Risk warning:** the game involves predicting BTC direction;
  the UI states it is a game with points only and no monetary reward.
  (No trading product is offered.)
- [x] **Agent ID not used as a wallet-lookup tool:** Agent ID is used
  only as a gate for the voter's own address.

## Open items before submission (as of 2026-11-19)

1. **Submission channel NOT FOUND.** The announcement gives no form
   URL or portal for project submissions — only "submit … during the
   Submission Period. No registration needed." Monitor the official
   announcement page, @BinanceWallet, and BNB Chain channels; never use
   a third-party form. Deadline: 9 Dec 2026 15:00 WIB.
2. **Deployment not done.** Needs: wallet re-pair (session expired
   since 2026-11-07) + BNB gas (~0.0021 BNB at 1 gwei; the wallet held
   only 0.00011476 BNB on 2026-11-19) + the user's fresh confirmation.
3. **Frontend hosting not done.** Deploy `frontend/` to GitHub Pages
   as-is and set the contract address in `app.js` CONFIG after step 2.
4. **≥30 Agent ID interactors needed** for the Innovation Award (and
   Pioneer ranking counts interacting Agent ID addresses). No outreach
   plan exists yet — this is the real bottleneck.
