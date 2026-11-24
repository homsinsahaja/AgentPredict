// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @notice Minimal interface for the Agent ID registry (SPACE ID Agent ID on BSC).
/// @dev Verified on-chain 2026-11-19: the registry ONLY exposes `balanceOf`.
///      `name()`, `symbol()`, `totalSupply()` and `supportsInterface()` all REVERT,
///      so this contract must never call them.
interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

/// @notice Minimal Chainlink AggregatorV3 interface (only what we read).
interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title AgentPredict — Agent ID-gated daily BTC direction prediction
/// @notice One round per UTC day. Agent ID holders vote UP or DOWN on whether BTC
///         will close the day above the round's reference price. Voting is free
///         except gas: no stakes, no fees, no token, no prizes, no promised
///         returns. Points only: +10 for a correct vote, +1 for voting at all.
/// @dev How rounds work (lazy, keeper-free):
///       - A round's reference price is the Chainlink BTC/USD price observed when
///         the FIRST vote of that UTC day arrives (there is no transaction at
///         midnight, so the reference is the first observed price of the day).
///       - When the first vote of a NEW day arrives, the previous day's round is
///         resolved against the current Chainlink price and the new round opens
///         with that same price as its reference.
///       - A tie (final price == reference price) counts as UP.
///       - Points for a vote are credited lazily: when you vote on a new day,
///         your previous day's vote is settled automatically; any older unsettled
///         vote can be settled anytime with `settle(dayId)`.
///       - Streak = consecutive UTC days voted. Voting on day D after voting on
///         day D-1 extends the streak, otherwise it restarts at 1.
contract AgentPredict is Ownable, Pausable {
    /// @notice Chainlink BTC/USD feed on BSC (verified on-chain 2026-11-19:
    ///         description "BTC / USD", 8 decimals, ~60s heartbeat).
    IAggregatorV3 public immutable btcFeed;
    /// @notice Agent ID registry on BSC (verified on-chain 2026-11-19:
    ///         `balanceOf` works; the user's wallet holds exactly 1 Agent ID).
    IAgentIdRegistry public immutable agentId;

    /// @notice Points for a correct prediction.
    uint256 public constant POINTS_CORRECT = 10;
    /// @notice Points for voting, even when the prediction is wrong.
    uint256 public constant POINTS_WRONG = 1;
    /// @notice Maximum age of a feed update we accept (heartbeat is ~60s).
    uint256 public constant MAX_FEED_AGE = 2 hours;

    struct Round {
        int256 referencePrice; // BTC/USD price (8 decimals) when the round opened
        int256 finalPrice; // BTC/USD price when the round was resolved (0 if unresolved)
        uint32 totalUp; // number of UP votes
        uint32 totalDown; // number of DOWN votes
        bool resolved; // true once resolved
        bool upWon; // true when finalPrice >= referencePrice (ties count as UP)
    }

    /// @notice Day id (UTC days since epoch) of the currently open round; 0 before the first vote.
    uint256 public currentDay;
    /// @notice Rounds by UTC day id.
    mapping(uint256 => Round) public rounds;
    /// @notice Whether an address already voted on a given day.
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    /// @notice The direction an address voted on a given day (meaningful only if hasVoted).
    mapping(uint256 => mapping(address => bool)) public voteUp;
    /// @notice Whether an address's vote for a given day has been settled into points.
    mapping(uint256 => mapping(address => bool)) public settled;

    /// @notice Total points per address.
    mapping(address => uint256) public points;
    /// @notice Current consecutive-days-voted streak per address.
    mapping(address => uint256) public streak;
    /// @notice Last UTC day an address voted on.
    mapping(address => uint256) public lastVotedDay;
    /// @notice Total votes ever cast per address.
    mapping(address => uint256) public totalVotes;

    /// @notice All addresses that ever voted (for leaderboard enumeration).
    address[] public voters;
    /// @notice voters array index + 1 (0 = never voted).
    mapping(address => uint256) public voterIndex;

    event RoundStarted(uint256 indexed dayId, int256 referencePrice);
    event Voted(uint256 indexed dayId, address indexed voter, bool up, uint32 totalUp, uint32 totalDown);
    event RoundResolved(uint256 indexed dayId, int256 finalPrice, bool upWon);
    event PointsSettled(address indexed voter, uint256 indexed dayId, uint256 pointsAwarded);

    error NotAgentIdHolder();
    error AlreadyVoted();
    error FeedStale();
    error FeedInvalidPrice();
    error RoundNotResolved();
    error AlreadySettled();
    error NoVote();

    constructor(address registry, address feed) Ownable(msg.sender) {
        require(registry != address(0) && feed != address(0), "zero address");
        require(registry.code.length > 0 && feed.code.length > 0, "not a contract");
        agentId = IAgentIdRegistry(registry);
        btcFeed = IAggregatorV3(feed);
        // The BTC/USD feed must be 8 decimals; anything else means misconfiguration.
        require(btcFeed.decimals() == 8, "feed must be 8 decimals");
    }

    /// @notice Current UTC day id.
    function today() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /// @notice Vote on today's round. One vote per Agent ID address per day.
    /// @param up true = BTC closes above the reference price, false = below.
    function vote(bool up) external whenNotPaused {
        if (agentId.balanceOf(msg.sender) == 0) revert NotAgentIdHolder();
        uint256 day = today();
        _rollover(day);
        if (hasVoted[day][msg.sender]) revert AlreadyVoted();

        // Settle yesterday's vote automatically when returning to vote.
        if (day > 0) _settleVote(msg.sender, day - 1);

        hasVoted[day][msg.sender] = true;
        voteUp[day][msg.sender] = up;
        if (up) {
            rounds[day].totalUp += 1;
        } else {
            rounds[day].totalDown += 1;
        }

        // Streak: consecutive days only.
        if (lastVotedDay[msg.sender] == day - 1) {
            streak[msg.sender] += 1;
        } else {
            streak[msg.sender] = 1;
        }
        lastVotedDay[msg.sender] = day;
        totalVotes[msg.sender] += 1;

        if (voterIndex[msg.sender] == 0) {
            voters.push(msg.sender);
            voterIndex[msg.sender] = voters.length;
        }

        emit Voted(day, msg.sender, up, rounds[day].totalUp, rounds[day].totalDown);
    }

    /// @notice Settle my vote for a resolved round into points.
    ///         Anyone can settle only their own votes. Works even while paused.
    function settle(uint256 dayId) external {
        if (!hasVoted[dayId][msg.sender]) revert NoVote();
        if (!rounds[dayId].resolved) revert RoundNotResolved();
        if (settled[dayId][msg.sender]) revert AlreadySettled();
        _credit(msg.sender, dayId);
    }

    /// @notice Points my vote for `dayId` would earn if settled now (0 if not settleable).
    function pendingPoints(address voter, uint256 dayId) external view returns (uint256) {
        if (!hasVoted[dayId][voter] || settled[dayId][voter] || !rounds[dayId].resolved) return 0;
        return voteUp[dayId][voter] == rounds[dayId].upWon ? POINTS_CORRECT : POINTS_WRONG;
    }

    /// @notice Full round state for a UTC day id.
    function getRound(uint256 dayId) external view returns (Round memory) {
        return rounds[dayId];
    }

    /// @notice Points, streak, last voted day and total votes for an address.
    function getVoterStats(address voter)
        external
        view
        returns (uint256 points_, uint256 streak_, uint256 lastVotedDay_, uint256 totalVotes_)
    {
        return (points[voter], streak[voter], lastVotedDay[voter], totalVotes[voter]);
    }

    /// @notice Number of distinct addresses that ever voted.
    function voterCount() external view returns (uint256) {
        return voters.length;
    }

    /// @notice Voter address at an index (for leaderboard enumeration).
    function voterAt(uint256 index) external view returns (address) {
        return voters[index];
    }

    /// @notice Emergency pause of voting only. Settlement stays available.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resume voting.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @dev Resolve the previous round (if it had votes) and open today's round.
    function _rollover(uint256 day) internal {
        if (day <= currentDay) return;
        int256 price = _readFeed();
        if (currentDay != 0) {
            Round storage prev = rounds[currentDay];
            if (!prev.resolved && (prev.totalUp + prev.totalDown) > 0) {
                prev.resolved = true;
                prev.finalPrice = price;
                prev.upWon = price >= prev.referencePrice;
                emit RoundResolved(currentDay, price, prev.upWon);
            }
        }
        currentDay = day;
        rounds[day].referencePrice = price;
        emit RoundStarted(day, price);
    }

    /// @dev Credit points for one vote. No-op unless the vote exists, the round
    ///      is resolved, and it has not been settled yet.
    function _settleVote(address voter, uint256 dayId) internal {
        if (!hasVoted[dayId][voter] || settled[dayId][voter]) return;
        if (!rounds[dayId].resolved) return;
        _credit(voter, dayId);
    }

    /// @dev Award points for a vote and mark it settled. Caller must have checked settleability.
    function _credit(address voter, uint256 dayId) internal {
        uint256 awarded = voteUp[dayId][voter] == rounds[dayId].upWon ? POINTS_CORRECT : POINTS_WRONG;
        settled[dayId][voter] = true;
        points[voter] += awarded;
        emit PointsSettled(voter, dayId, awarded);
    }

    /// @dev Read the Chainlink price with staleness and sanity guards.
    function _readFeed() internal view returns (int256) {
        (, int256 answer,, uint256 updatedAt,) = btcFeed.latestRoundData();
        if (answer <= 0) revert FeedInvalidPrice();
        if (updatedAt == 0 || updatedAt > block.timestamp || block.timestamp - updatedAt > MAX_FEED_AGE) {
            revert FeedStale();
        }
        return answer;
    }
}
