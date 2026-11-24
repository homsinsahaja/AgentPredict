// AgentPredict frontend — plain JavaScript + ethers v6 (vendored).
// No build step. Deploy this folder as-is to any static host (e.g. GitHub Pages).
// Wallet access is via the injected provider ONLY (window.ethereum: MetaMask,
// Binance Wallet extension / in-app browser). No QR codes, no pairing codes,
// no external sign-in. The only signature the user ever approves is their own
// vote transaction, confirmed in their own wallet.

const CONFIG = {
  // TODO (deployment): paste the deployed AgentPredict address here.
  CONTRACT_ADDRESS: "0x0000000000000000000000000000000000000000",
  AGENT_ID_REGISTRY: "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F",
  CHAINLINK_BTC_USD: "0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf",
  BSC_CHAIN_ID: 56,
  BSC_RPC: "https://bsc.publicnode.com",
};

const GAME_ABI = [
  "function vote(bool up) external",
  "function settle(uint256 dayId) external",
  "function today() view returns (uint256)",
  "function currentDay() view returns (uint256)",
  "function getRound(uint256 dayId) view returns (tuple(int256 referencePrice, int256 finalPrice, uint32 totalUp, uint32 totalDown, bool resolved, bool upWon))",
  "function hasVoted(uint256 dayId, address voter) view returns (bool)",
  "function voteUp(uint256 dayId, address voter) view returns (bool)",
  "function getVoterStats(address voter) view returns (uint256 points, uint256 streak, uint256 lastVotedDay, uint256 totalVotes)",
  "function voterCount() view returns (uint256)",
  "function voterAt(uint256 index) view returns (address)",
  "function pendingPoints(address voter, uint256 dayId) view returns (uint256)",
  "function paused() view returns (bool)",
];
const REGISTRY_ABI = ["function balanceOf(address owner) view returns (uint256)"];
const FEED_ABI = [
  "function decimals() view returns (uint8)",
  "function latestRoundData() view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)",
];

const $ = (id) => document.getElementById(id);
const isDeployed = () => CONFIG.CONTRACT_ADDRESS !== "0x0000000000000000000000000000000000000000";
const fmtUsd = (v8) => "$" + (Number(v8) / 1e8).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const shortAddr = (a) => a.slice(0, 6) + "…" + a.slice(-4);
const dayToDate = (dayId) => new Date(dayId * 86400 * 1000).toISOString().slice(0, 10);

let readProvider; // public RPC, for visitors without a wallet
let browserProvider; // injected wallet provider
let signer;
let userAddress = null;
let game; // read-only contract instance
let gameWithSigner;
let feed;

function notice(msg, kind) {
  const el = $("notice");
  el.textContent = msg;
  el.className = kind || "";
  el.classList.remove("hidden");
}

async function init() {
  readProvider = new ethers.JsonRpcProvider(CONFIG.BSC_RPC, CONFIG.BSC_CHAIN_ID);
  feed = new ethers.Contract(CONFIG.CHAINLINK_BTC_USD, FEED_ABI, readProvider);

  if (!isDeployed()) {
    notice("AgentPredict is not deployed yet — the contract address is still a placeholder. Come back after launch.", "error");
    return;
  }
  game = new ethers.Contract(CONFIG.CONTRACT_ADDRESS, GAME_ABI, readProvider);
  const link = $("contract-link");
  link.textContent = shortAddr(CONFIG.CONTRACT_ADDRESS);
  link.href = "https://bscscan.com/address/" + CONFIG.CONTRACT_ADDRESS;

  await refreshPublic();
  setInterval(tickCountdown, 1000);
  setInterval(refreshLivePrice, 30000);

  if (window.ethereum) {
    $("connect-btn").addEventListener("click", connectWallet);
    window.ethereum.on("accountsChanged", () => location.reload());
    window.ethereum.on("chainChanged", () => location.reload());
  } else {
    $("connect-btn").disabled = true;
    $("wallet-status").textContent = "No wallet found — install MetaMask or open this page in the Binance Wallet app browser.";
  }
}

async function refreshPublic() {
  try {
    const [today, round, live] = await Promise.all([
      game.today(),
      game.getRound(await game.today()),
      feed.latestRoundData(),
    ]);
    const paused = await game.paused();
    $("round-card").classList.remove("hidden");
    $("leaderboard-card").classList.remove("hidden");
    $("history-card").classList.remove("hidden");
    $("ref-price").textContent = round.referencePrice === 0n ? "Round opens on first vote" : fmtUsd(round.referencePrice);
    $("live-price").textContent = fmtUsd(live.answer);
    $("total-up").textContent = round.totalUp;
    $("total-down").textContent = round.totalDown;
    if (paused) notice("Voting is paused by the owner (emergency pause).", "error");
    await refreshLeaderboard();
    await refreshHistory(Number(today));
  } catch (e) {
    notice("Could not load round data: " + (e.reason || e.message), "error");
  }
}

async function refreshLivePrice() {
  try {
    const live = await feed.latestRoundData();
    $("live-price").textContent = fmtUsd(live.answer);
  } catch (_) { /* keep last price on transient errors */ }
}

function tickCountdown() {
  const now = new Date();
  const midnight = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1, 0, 0, 0));
  let s = Math.max(0, Math.floor((midnight - now) / 1000));
  const h = String(Math.floor(s / 3600)).padStart(2, "0");
  const m = String(Math.floor((s % 3600) / 60)).padStart(2, "0");
  const sec = String(s % 60).padStart(2, "0");
  $("countdown").textContent = `${h}:${m}:${sec} UTC`;
}

async function connectWallet() {
  try {
    browserProvider = new ethers.BrowserProvider(window.ethereum);
    const accounts = await browserProvider.send("eth_requestAccounts", []);
    userAddress = accounts[0];
    const network = await browserProvider.getNetwork();
    if (Number(network.chainId) !== CONFIG.BSC_CHAIN_ID) {
      await switchToBsc();
    }
    signer = await browserProvider.getSigner();
    gameWithSigner = new ethers.Contract(CONFIG.CONTRACT_ADDRESS, GAME_ABI, signer);
    $("wallet-status").textContent = "Connected: " + shortAddr(userAddress);
    $("connect-btn").disabled = true;
    await refreshUser();
  } catch (e) {
    notice("Could not connect wallet: " + (e.reason || e.message), "error");
  }
}

async function switchToBsc() {
  try {
    await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: "0x38" }] });
  } catch (e) {
    if (e.code === 4902) {
      await window.ethereum.request({
        method: "wallet_addEthereumChain",
        params: [{
          chainId: "0x38", chainName: "BNB Smart Chain",
          nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 },
          rpcUrls: ["https://bsc-dataseed.binance.org"],
          blockExplorerUrls: ["https://bscscan.com"],
        }],
      });
    } else {
      throw e;
    }
  }
}

async function refreshUser() {
  const registry = new ethers.Contract(CONFIG.AGENT_ID_REGISTRY, REGISTRY_ABI, readProvider);
  const balance = await registry.balanceOf(userAddress);
  if (balance === 0n) {
    notice("This wallet does not hold an Agent ID, so it cannot vote. An Agent ID is free to claim in the Binance app: Wallet → homepage banner → Agent ID.", "error");
    return;
  }
  const today = await game.today();
  const [stats, voted, pending] = await Promise.all([
    game.getVoterStats(userAddress),
    game.hasVoted(today, userAddress),
    today > 0n ? game.pendingPoints(userAddress, today - 1n) : 0n,
  ]);
  $("mystats-card").classList.remove("hidden");
  $("my-points").textContent = stats.points.toString();
  $("my-streak").textContent = stats.streak.toString();
  $("my-votes").textContent = stats.totalVotes.toString();
  $("my-pending").textContent = pending.toString();
  if (pending > 0n) {
    const btn = $("settle-btn");
    btn.classList.remove("hidden");
    btn.onclick = async () => {
      try {
        $("vote-status").textContent = "Confirm the transaction in your wallet…";
        const tx = await gameWithSigner.settle(today - 1n);
        await tx.wait();
        $("vote-status").textContent = "Points collected.";
        await refreshPublic();
        await refreshUser();
      } catch (e) {
        $("vote-status").textContent = "Collecting failed: " + (e.reason || e.message);
      }
    };
  }
  if (voted) {
    const up = await game.voteUp(today, userAddress);
    $("vote-status").textContent = "You already voted " + (up ? "▲ Up" : "▼ Down") + " today. Come back tomorrow for the next round.";
    $("vote-up").disabled = true;
    $("vote-down").disabled = true;
  } else {
    $("vote-up").disabled = false;
    $("vote-down").disabled = false;
    $("vote-up").onclick = () => castVote(true);
    $("vote-down").onclick = () => castVote(false);
  }
}

async function castVote(up) {
  try {
    $("vote-status").textContent = "Confirm the transaction in your wallet…";
    $("vote-up").disabled = true;
    $("vote-down").disabled = true;
    const tx = await gameWithSigner.vote(up);
    $("vote-status").textContent = "Vote sent — waiting for confirmation…";
    await tx.wait();
    $("vote-status").textContent = "Vote confirmed. Good luck!";
    await refreshPublic();
    await refreshUser();
  } catch (e) {
    $("vote-status").textContent = "Vote failed: " + (e.reason || e.message);
    $("vote-up").disabled = false;
    $("vote-down").disabled = false;
  }
}

async function refreshLeaderboard() {
  try {
    const count = Number(await game.voterCount());
    const list = $("leaderboard");
    if (count === 0) {
      list.innerHTML = "<li>No votes yet — be the first.</li>";
      return;
    }
    const addrs = [];
    const cap = Math.min(count, 500);
    for (let i = 0; i < cap; i++) addrs.push(await game.voterAt(i));
    const rows = [];
    for (let i = 0; i < addrs.length; i += 25) {
      const batch = await Promise.all(addrs.slice(i, i + 25).map((a) => game.getVoterStats(a)));
      batch.forEach((s, j) => rows.push({ addr: addrs[i + j], points: Number(s.points), streak: Number(s.streak) }));
    }
    rows.sort((a, b) => b.points - a.points || b.streak - a.streak);
    list.innerHTML = rows.slice(0, 10).map((r, i) =>
      `<li><span class="addr">${shortAddr(r.addr)}</span> — ${r.points} pts · 🔥 ${r.streak}-day streak</li>`
    ).join("");
  } catch (_) {
    $("leaderboard").innerHTML = "<li>Could not load the leaderboard.</li>";
  }
}

async function refreshHistory(today) {
  try {
    const body = $("history-body");
    let html = "";
    for (let d = today; d > today - 7 && d >= 0; d--) {
      const r = await game.getRound(d);
      if (r.referencePrice === 0n) continue;
      const result = !r.resolved ? "Open" : (r.upWon ? "▲ Up" : "▼ Down");
      const close = !r.resolved ? "—" : fmtUsd(r.finalPrice);
      html += `<tr><td>${dayToDate(d)}</td><td>${fmtUsd(r.referencePrice)}</td><td>${close}</td><td>${result}</td><td>${Number(r.totalUp) + Number(r.totalDown)}</td></tr>`;
    }
    body.innerHTML = html || '<tr><td colspan="5">No rounds yet.</td></tr>';
  } catch (_) {
    $("history-body").innerHTML = '<tr><td colspan="5">Could not load history.</td></tr>';
  }
}

document.addEventListener("DOMContentLoaded", init);
