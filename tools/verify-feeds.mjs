// Verify the two on-chain facts AgentPredict depends on:
//  1. Chainlink BTC/USD feed on BSC — candidate 0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf
//     (evmquery.com, cross-checked vs Chainlink ref data; also used by predictfun-btc-bot)
//     NOTE: 0x0567F232... is the BNB/USD feed, NOT BTC/USD — verified on-chain 2026-11-19.
//  2. Agent ID registry (0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F)
// Read-only eth_calls. Run: node tools/verify-feeds.mjs
import { JsonRpcProvider, Contract, getAddress } from "ethers";

const RPCS = [
  "https://bsc.publicnode.com",
  "https://rpc-bsc.48.club",
  "https://bsc-dataseed1.defibit.io",
];

const FEED = getAddress("0x264990fbd0a4796a3e3d8e37c4d5f87a3aca5ebf"); // BTC/USD candidate — verify on-chain below
const REGISTRY = getAddress("0x60b9262456de011f7d15a54cdd8c48baaa8b022f");
const USER = "0xbb1777a4ab27cd1b871371add8eceb645e69354a";

const FEED_ABI = [
  "function decimals() view returns (uint8)",
  "function description() view returns (string)",
  "function latestAnswer() view returns (int256)",
  "function latestRoundData() view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)",
];
const REGISTRY_ABI = [
  // ONLY balanceOf is supported: name()/symbol()/totalSupply()/supportsInterface() all REVERT on this contract (verified 2026-11-19).
  "function balanceOf(address) view returns (uint256)",
];

async function tryRpc(label, fn) {
  for (const url of RPCS) {
    try {
      const provider = new JsonRpcProvider(url, 56, { batchMaxCount: 1, polling: false });
      const out = await fn(provider);
      console.log(`[${label}] via ${url}`);
      return out;
    } catch (e) {
      console.log(`[${label}] ${url} failed: ${String(e.message).slice(0, 120)}`);
    }
  }
  throw new Error(`${label}: all RPCs failed`);
}

const feed = await tryRpc("FEED", async (p) => {
  const c = new Contract(FEED, FEED_ABI, p);
  const [decimals, description, latestAnswer, rd] = await Promise.all([
    c.decimals(), c.description(), c.latestAnswer(), c.latestRoundData(),
  ]);
  return { decimals: Number(decimals), description, latestAnswer: latestAnswer.toString(), roundId: rd[0].toString(), updatedAt: new Date(Number(rd[3]) * 1000).toISOString() };
});
console.log("FEED:", JSON.stringify(feed, null, 2));
console.log("FEED price USD:", Number(feed.latestAnswer) / 10 ** feed.decimals);

const reg = await tryRpc("REGISTRY", async (p) => {
  const c = new Contract(REGISTRY, REGISTRY_ABI, p);
  const bal = await c.balanceOf(USER);
  return { userBalance: bal.toString() };
});
console.log("REGISTRY:", JSON.stringify(reg, null, 2));

// Chainlink sanity: price must be in a plausible BTC range (10k–500k USD)
const price = Number(feed.latestAnswer) / 10 ** feed.decimals;
if (price < 10000 || price > 500000) {
  console.log("FEED SANITY: FAIL — price outside plausible BTC range");
  process.exit(2);
}
if (feed.description.toLowerCase().includes("btc") && feed.description.toLowerCase().includes("usd")) {
  console.log("FEED SANITY: PASS — description names BTC/USD, price plausible");
} else {
  console.log("FEED SANITY: WARN — description does not clearly say BTC/USD:", feed.description);
}
console.log("REGISTRY SANITY:", reg.userBalance === "1" ? "PASS — user wallet holds exactly 1 Agent ID" : `NOTE — user balanceOf = ${reg.userBalance}`);
