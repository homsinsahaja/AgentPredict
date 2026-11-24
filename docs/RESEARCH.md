# AgentPredict — research notes

Verified 2026-11-19 (all on-chain checks via live BSC RPC calls;
web checks via the official announcement page and public profiles).

## 1. Hackathon (official announcement)

- Source: https://www.binance.com/en/support/announcement/detail/95f5dbe0ea674a48a739b59e046648bf
  (also mirrored on Binance Square: https://www.binance.com/en/square/post/389517345917641)
- Organizers: Binance Wallet + BNB Chain. Prize pool 60,000 USDC:
  Project Awards 58,000 USDC (Pioneer top-10 by on-chain metrics +
  Innovation top-10 by judging panel, 29,000 USDC each;
  1st $10k, 2nd $6k, 3rd $4k, 4th $3k, 5th $2k, 6th–10th $800 each)
  + Community Promotion 2,000 USDC (20 winners × $100 for X posts).
- Submission period: 2026-11-18 08:00 UTC → 2026-12-09 08:00 UTC
  (15:00 WIB 9 Dec 2026). Internal review 9–17 Dec; public review
  17–20 Dec; rewards within 14 business days after the public
  announcement.
- Requirements: deployed on BNB Chain; actively uses Agent ID; contract
  source verified and open-source on BscScan; at most one project per team;
  each project at most one award; winners also get a two-digit Agent ID
  claim spot.
- Innovation Award eligibility: live product + **at least 30 Agent ID
  addresses** interacted with the contract(s) during the period.
  Pioneer Award: top-10 by weighted on-chain metrics (interacting Agent ID
  addresses, tx volume/count).
- Judging criteria (Innovation): Agent ID Application Depth 30% /
  Practicality & Feasibility 25% / Product Completion 25% / Innovation 20%.
- Safety red lines (violation = disqualification): no web QR-code login
  for Agentic Wallet; no prompts/flows bypassing user transaction
  confirmation; no unauthorized asset transfers; contracts open-source
  with disclosed owner permissions; no "Binance"/"BNB" brand impersonation
  in names/domains; never collect seed phrases, private keys, API secrets,
  or pairing codes; never promise returns ("passive income" etc.); risk
  warnings for trading products; Agent ID must not be packaged as a tool
  to look up other people's wallets by name.

## 2. Project submission mechanism — NOT FOUND (open item)

The announcement says step 3 is: "Submit your project name, website,
contract address(es), Agent ID usage description, and other required
materials during the Submission Period. No registration needed."
**No form URL, portal, email, or survey link for project submissions
exists in the announcement text.** Checked 2026-11-19:

- Full announcement page (277 lines, crawled 2026-11-19 07:39 UTC):
  the only survey link is the Community Promotion one (see below).
- Binance Square mirror post: same announcement text, no form link.
- Web searches for "Binance Wallet BNB Chain Agent ID Hackathon submit
  project form" (2026-11-19): no submission portal found.
- @BinanceWallet X profile checked read-only 2026-11-19 15:05 WIB
  (guest view, 5 latest posts only): the only hackathon post is the
  pinned one, linking ONLY to the announcement page itself
  (binance.com/en/support/announcement/detail/95f5dbe0ea674a48a739b59e046648bf),
  not to any submission form/portal. No other visible 18–19 Nov post
  mentions the hackathon. Likeliest reading: Binance has not published
  the project submission channel yet (hackathon is 1 day old); re-check
  official channels in the coming days.
- **Do NOT use a third-party form.** The submission channel must be
  found in an official source (announcement page update, @BinanceWallet
  on X, BNB Chain channels) before 9 Dec 2026 15:00 WIB, and monitored
  until then.

The one survey link that DOES exist is for the **Community Promotion**
award only (X-post link submission), not for projects:
https://app.binance.com/uni-qr/user-survey/ff6832f8d2984af289068c9450a3c98c
— "Submit your X link via the official campaign survey" (announcement
step for the promotion award). The fetched page only renders a
Binance-app download prompt, so its form fields could not be read here.

## 3. Agent ID contract — VERIFIED on-chain 2026-11-19

- Address: `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` (matches the
  announcement's table: "SPACE ID Agent ID, Symbol: AI, Standard:
  ERC-721, Non-transferable").
- Code: 8,756 bytes on BSC mainnet.
- `balanceOf(0xbb1777a4ab27cd1b871371add8eceb645e69354a)` (the user's
  wallet) = **1** — the user holds an Agent ID.
- `name()`, `symbol()`, `totalSupply()`, `supportsInterface()` all
  **REVERT**. Consequence: AgentPredict only ever calls `balanceOf`.
- Script: `tools/verify-feeds.mjs`.

## 4. Chainlink BTC/USD feed on BSC — VERIFIED on-chain 2026-11-19

- Address: `0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf`
- `description()` = **"BTC / USD"**, `decimals()` = **8**.
- `latestAnswer` at check time: **$63,535.29**,
  `updatedAt` 2026-11-19T07:43:33Z (fresh; ~60s heartbeat).
- Cross-checked against Chainlink reference data and the Predict.fun
  settlement-feed usage (predictfun-btc-bot on GitHub uses this address).
- **Correction made during research:** the address first believed to be
  the BTC feed, `0x0567F2323251f0AAB15c8dFb1967E4e8A7D42aeE`, is actually
  the **BNB/USD feed** (description "BNB / USD", price $588.37). Building
  on it would have settled BTC predictions against the BNB price. The
  correct BTC feed above was used instead.
- No fallback was needed: the feed is live, fresh, and correct. If it
  ever goes stale, the contract reverts `FeedStale` rather than resolving
  on old data (2-hour staleness guard vs a ~60s heartbeat).
- Script: `tools/verify-feeds.mjs`.

## 5. BSC chain facts measured 2026-11-19

- Block time ~**0.45 s/block** (1,000 blocks span 450 s), measured on
  bsc.publicnode.com and rpc-bsc.48.club; latest block ~134,466,300.
- Free public RPCs do **not** serve archive account state:
  `eth_getBalance`/`eth_getCode` at old blocks fail
  (publicnode: 403 "Archive requests require a personal token";
  48.club / defibit: "historical state not available" / "missing trie
  node"), although `eth_call` at old blocks works.
  Consequences: (a) foundry fork tests cannot rewind the chain — the
  resolution fork test uses a documented `mockCall` that patches only
  the feed's timestamp fields while keeping the real on-chain price
  (see `test/AgentPredictFork.t.sol`); (b) ankr's free RPC now requires
  an API key; 1rpc.io's free plan is rate-limited; bsc-rpc.publicnode.com
  returns 403.

## 6. Competitors seen live 2026-11-19

- **AgentWall** (febry10.github.io/agentwall): daily check-ins, message
  wall, BNB tips between Agent ID holders; verified contract; recruiting
  its first 30 agents. Promoted on X/Facebook the same day.
- **Agent ID arena shooter game**: on-chain scores tied to the player's
  `.ai` name; leaderboard entry 13,730 seen.
- **AgentLabs** (agentlabs.fun): "a daily experiment lab for agents" —
  one specimen a day, Agent ID-gated, $LAB token rewards, free first
  specimen per experiment (with an on-chain arithmetic question).
- AgentPredict differentiates: a **prediction game** (daily BTC
  direction, points + streaks + leaderboard), not check-ins, a shooter,
  or a specimen lab. No token, no stakes, no fees.
