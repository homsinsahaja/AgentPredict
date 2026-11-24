// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AgentPredict} from "../src/AgentPredict.sol";

/// @notice Fork tests against the REAL BSC contracts.
///         Run with: forge test --match-contract AgentPredictForkTest
///         Fork RPC: bsc.publicnode.com (see foundry.toml [rpc_endpoints]).
contract AgentPredictForkTest is Test {
    address public constant REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    address public constant FEED = 0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf;
    // The user's wallet; holds exactly 1 Agent ID on BSC mainnet.
    address public constant USER = 0xbb1777a4ab27cD1B871371ADD8ECEB645e69354a;

    AgentPredict public game;

    function setUp() public {
        vm.createSelectFork("bsc");
        game = new AgentPredict(REGISTRY, FEED);
    }

    /// @notice The Agent ID gate works against the real registry.
    function testFork_RealRegistryGate() public {
        // Real user wallet holds exactly 1 Agent ID.
        assertEq(game.agentId().balanceOf(USER), 1);
        // A random address holds none.
        assertEq(game.agentId().balanceOf(address(0x1234)), 0);

        // The real holder can vote on the fork.
        vm.prank(USER);
        game.vote(true);
        assertTrue(game.hasVoted(game.today(), USER));

        // A non-holder cannot.
        vm.prank(address(0x1234));
        vm.expectRevert(AgentPredict.NotAgentIdHolder.selector);
        game.vote(true);
    }

    /// @notice The real Chainlink BTC/USD feed is readable and sane.
    function testFork_RealFeedIsLive() public {
        (, int256 answer,, uint256 updatedAt,) = game.btcFeed().latestRoundData();
        // $10,000 - $500,000 at 8 decimals.
        assertGe(answer, int256(10_000 * 1e8));
        assertLe(answer, int256(500_000 * 1e8));
        assertEq(game.btcFeed().decimals(), 8);
        // Fresh: updated within the last 2 hours at fork time.
        assertLe(block.timestamp - updatedAt, 2 hours);

        // Voting reads the real feed as the round reference.
        vm.prank(USER);
        game.vote(true);
        assertEq(game.getRound(game.today()).referencePrice, answer);
    }

    /// @notice Full round lifecycle on the fork: vote, cross UTC midnight,
    ///         vote again -> previous round resolves and points settle.
    /// @dev The fork's Chainlink feed state is frozen at fork time, so after
    ///      warping +1 day the real feed looks stale (>2h) and the contract
    ///      would (correctly) revert. To keep the test runnable, the feed's
    ///      `latestRoundData` return is patched ONLY for its timestamp fields:
    ///      the ANSWER is the real on-chain price read from the feed before
    ///      the warp. What stays fully real: the Agent ID gate (real registry,
    ///      real holder), the price value, and the resolution/points logic.
    ///      Free BSC RPCs prune old account state, so rewinding the fork to
    ///      just before midnight is not possible from this VM (verified:
    ///      eth_getBalance at ~8h-old blocks fails on publicnode/48.club/
    ///      defibit; ankr needs an API key, 1rpc is rate-limited).
    function testFork_ResolutionAgainstRealFeed() public {
        uint256 day0 = game.today();

        // Read the REAL feed price before warping.
        (, int256 realAnswer,,,) = game.btcFeed().latestRoundData();
        assertGt(realAnswer, 0);

        vm.prank(USER);
        game.vote(true);
        int256 refPrice = game.getRound(day0).referencePrice;
        assertEq(refPrice, realAnswer);

        // Cross midnight. Patch only the feed timestamps to the new time.
        vm.warp(block.timestamp + 1 days + 1800);
        vm.mockCall(
            FEED,
            abi.encodeWithSelector(bytes4(0xfeaf968c)), // latestRoundData()
            abi.encode(uint80(1), realAnswer, block.timestamp, block.timestamp, uint80(1))
        );

        vm.prank(USER);
        game.vote(false);

        AgentPredict.Round memory r0 = game.getRound(day0);
        assertTrue(r0.resolved);
        assertEq(r0.finalPrice, realAnswer);
        assertEq(r0.upWon, realAnswer >= refPrice);
        // USER voted UP on day 0; auto-settled on the day-1 vote.
        uint256 expected = r0.upWon ? 10 : 1;
        assertEq(game.points(USER), expected);
        assertEq(game.streak(USER), 2);
    }
}
