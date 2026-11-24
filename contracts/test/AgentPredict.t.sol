// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AgentPredict} from "../src/AgentPredict.sol";

contract MockAgentId {
    mapping(address => uint256) public balances;

    function setBalance(address who, uint256 bal) external {
        balances[who] = bal;
    }

    function balanceOf(address who) external view returns (uint256) {
        return balances[who];
    }
}

contract MockFeed {
    int256 public price;
    uint256 public updatedAt;
    uint8 public decimalsValue = 8;

    function setPrice(int256 p, uint256 t) external {
        price = p;
        updatedAt = t;
    }

    function setDecimals(uint8 d) external {
        decimalsValue = d;
    }

    function decimals() external view returns (uint8) {
        return decimalsValue;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, price, updatedAt, updatedAt, 1);
    }
}

contract AgentPredictTest is Test {
    AgentPredict public game;
    MockAgentId public registry;
    MockFeed public feed;

    address public owner = address(this);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public carol = address(0xCA901);

    // A UTC midnight; day id = DAY0 / 1 days.
    uint256 public constant DAY0 = 1795564800; // a UTC midnight in Nov 2026
    int256 public constant PRICE0 = 63_500_00000000; // $63,500.00 (8 decimals)

    function setUp() public {
        registry = new MockAgentId();
        feed = new MockFeed();
        feed.setPrice(PRICE0, DAY0);
        game = new AgentPredict(address(registry), address(feed));
        registry.setBalance(alice, 1);
        registry.setBalance(bob, 1);
        registry.setBalance(carol, 1);
        vm.warp(DAY0 + 3600); // day 0, 01:00 UTC
        feed.setPrice(PRICE0, block.timestamp);
    }

    function _day() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }

    // ---- constructor ----

    function test_ConstructorRejectsZeroAddress() public {
        vm.expectRevert("zero address");
        new AgentPredict(address(0), address(feed));
        vm.expectRevert("zero address");
        new AgentPredict(address(registry), address(0));
    }

    function test_ConstructorRejectsNonContract() public {
        vm.expectRevert("not a contract");
        new AgentPredict(address(0xDEAD), address(feed));
    }

    function test_ConstructorRejectsWrongDecimals() public {
        MockFeed bad = new MockFeed();
        bad.setDecimals(18);
        vm.expectRevert("feed must be 8 decimals");
        new AgentPredict(address(registry), address(bad));
    }

    // ---- voting ----

    function test_NonHolderCannotVote() public {
        address stranger = address(0x9999);
        vm.prank(stranger);
        vm.expectRevert(AgentPredict.NotAgentIdHolder.selector);
        game.vote(true);
    }

    function test_FirstVoteOpensRound() public {
        vm.prank(alice);
        game.vote(true);
        AgentPredict.Round memory r = game.getRound(_day());
        assertEq(r.referencePrice, PRICE0);
        assertEq(r.totalUp, 1);
        assertEq(r.totalDown, 0);
        assertFalse(r.resolved);
        assertTrue(game.hasVoted(_day(), alice));
        assertEq(game.streak(alice), 1);
        assertEq(game.voterCount(), 1);
        assertEq(game.voterAt(0), alice);
    }

    function test_DoubleVoteSameDayReverts() public {
        vm.prank(alice);
        game.vote(true);
        vm.prank(alice);
        vm.expectRevert(AgentPredict.AlreadyVoted.selector);
        game.vote(false);
    }

    function test_TwoVotersOppositeSides() public {
        vm.prank(alice);
        game.vote(true);
        vm.prank(bob);
        game.vote(false);
        AgentPredict.Round memory r = game.getRound(_day());
        assertEq(r.totalUp, 1);
        assertEq(r.totalDown, 1);
        assertEq(game.voterCount(), 2);
    }

    // ---- resolution: UP wins ----

    function test_RolloverResolvesUp() public {
        uint256 day0 = _day();
        vm.prank(alice);
        game.vote(true); // up
        vm.prank(bob);
        game.vote(false); // down

        // Next day, price ABOVE reference -> UP wins.
        vm.warp(DAY0 + 1 days + 3600);
        feed.setPrice(PRICE0 + 100_00000000, block.timestamp); // +$100
        vm.prank(alice);
        game.vote(true);

        AgentPredict.Round memory r0 = game.getRound(day0);
        assertTrue(r0.resolved);
        assertTrue(r0.upWon);
        assertEq(r0.finalPrice, PRICE0 + 100_00000000);

        // Alice's day-0 vote auto-settled on her new vote: correct -> +10.
        assertEq(game.points(alice), 10);
        assertEq(game.streak(alice), 2);
        // Bob has not returned: his day-0 vote is pending, not yet credited.
        assertEq(game.points(bob), 0);
        assertEq(game.pendingPoints(bob, day0), 1); // wrong -> +1
    }

    // ---- resolution: DOWN wins ----

    function test_RolloverResolvesDown() public {
        uint256 day0 = _day();
        vm.prank(alice);
        game.vote(true);
        vm.prank(bob);
        game.vote(false);

        vm.warp(DAY0 + 1 days + 3600);
        feed.setPrice(PRICE0 - 250_00000000, block.timestamp); // -$250
        vm.prank(bob);
        game.vote(false);

        AgentPredict.Round memory r0 = game.getRound(day0);
        assertTrue(r0.resolved);
        assertFalse(r0.upWon);
        // Bob correct -> +10; Alice wrong -> +1 when she settles.
        assertEq(game.points(bob), 10);
        assertEq(game.pendingPoints(alice, day0), 1);
    }

    // ---- tie counts as UP ----

    function test_TieCountsAsUp() public {
        uint256 day0 = _day();
        vm.prank(alice);
        game.vote(true);
        vm.prank(bob);
        game.vote(false);

        vm.warp(DAY0 + 1 days + 3600);
        feed.setPrice(PRICE0, block.timestamp); // exactly flat
        vm.prank(alice);
        game.vote(false);

        AgentPredict.Round memory r0 = game.getRound(day0);
        assertTrue(r0.resolved);
        assertTrue(r0.upWon);
        assertEq(game.points(alice), 10);
    }

    // ---- settle() ----

    function test_SettleManually() public {
        uint256 day0 = _day();
        vm.prank(alice);
        game.vote(true);
        vm.prank(bob);
        game.vote(false);

        vm.warp(DAY0 + 1 days + 3600);
        feed.setPrice(PRICE0 + 50_00000000, block.timestamp);
        // Trigger rollover with a third voter so the round resolves.
        vm.prank(carol);
        game.vote(true);

        // Bob settles manually: wrong -> +1.
        vm.prank(bob);
        game.settle(day0);
        assertEq(game.points(bob), 1);
        assertTrue(game.settled(day0, bob));
        assertEq(game.pendingPoints(bob, day0), 0);

        vm.prank(bob);
        vm.expectRevert(AgentPredict.AlreadySettled.selector);
        game.settle(day0);
    }

    function test_SettleUnresolvedReverts() public {
        vm.prank(alice);
        game.vote(true);
        vm.prank(alice);
        vm.expectRevert(AgentPredict.RoundNotResolved.selector);
        game.settle(_day());
    }

    function test_SettleWithoutVoteReverts() public {
        vm.prank(alice);
        game.vote(true);
        vm.prank(bob);
        vm.expectRevert(AgentPredict.NoVote.selector);
        game.settle(_day());
    }

    // ---- streaks ----

    function test_StreakResetsAfterGap() public {
        vm.prank(alice);
        game.vote(true); // day 0, streak 1
        // Skip a whole day, vote on day 2.
        vm.warp(DAY0 + 2 days + 3600);
        feed.setPrice(PRICE0, block.timestamp);
        vm.prank(alice);
        game.vote(true);
        assertEq(game.streak(alice), 1);
        // Her day-0 vote is still settleable (round 0 resolved at rollover).
        assertEq(game.pendingPoints(alice, _day() - 2), 10); // flat -> UP won, she voted up
    }

    function test_StreakBuildsThreeDays() public {
        vm.prank(alice);
        game.vote(true);
        vm.warp(DAY0 + 1 days + 3600);
        feed.setPrice(PRICE0 + 10_00000000, block.timestamp);
        vm.prank(alice);
        game.vote(true);
        vm.warp(DAY0 + 2 days + 3600);
        feed.setPrice(PRICE0 + 20_00000000, block.timestamp);
        vm.prank(alice);
        game.vote(false);
        assertEq(game.streak(alice), 3);
        // Day 0 correct (+10, settled on day-1 vote), day 1 correct (+10, settled on day-2 vote).
        assertEq(game.points(alice), 20);
    }

    // ---- empty-day rollover ----

    function test_SkippedEmptyDay() public {
        uint256 day0 = _day();
        vm.prank(alice);
        game.vote(true);
        // Nobody votes on day 1; vote on day 2.
        vm.warp(DAY0 + 2 days + 3600);
        feed.setPrice(PRICE0 + 5_00000000, block.timestamp);
        vm.prank(alice);
        game.vote(false);
        // Day 0 resolved; day 1 never existed as a round.
        assertTrue(game.getRound(day0).resolved);
        assertEq(game.getRound(day0 + 1).referencePrice, 0);
        assertEq(game.currentDay(), _day());
    }

    // ---- feed guards ----

    function test_StaleFeedReverts() public {
        // Feed last updated > 2h ago.
        feed.setPrice(PRICE0, block.timestamp - 2 hours - 1);
        vm.prank(alice);
        vm.expectRevert(AgentPredict.FeedStale.selector);
        game.vote(true);
    }

    function test_ZeroPriceReverts() public {
        feed.setPrice(0, block.timestamp);
        vm.prank(alice);
        vm.expectRevert(AgentPredict.FeedInvalidPrice.selector);
        game.vote(true);
    }

    function test_NegativePriceReverts() public {
        feed.setPrice(-1, block.timestamp);
        vm.prank(alice);
        vm.expectRevert(AgentPredict.FeedInvalidPrice.selector);
        game.vote(true);
    }

    // ---- pause ----

    function test_PauseBlocksVoteButNotSettle() public {
        vm.prank(alice);
        game.vote(true);
        vm.warp(DAY0 + 1 days + 3600);
        feed.setPrice(PRICE0 + 10_00000000, block.timestamp);
        vm.prank(carol);
        game.vote(true); // resolves day 0

        game.pause();
        vm.prank(bob);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        game.vote(true);

        // Settlement still works while paused.
        vm.prank(alice);
        game.settle(_day() - 1);
        assertEq(game.points(alice), 10);

        game.unpause();
        vm.prank(bob);
        game.vote(false);
        assertTrue(game.hasVoted(_day(), bob));
    }

    function test_OnlyOwnerCanPause() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        game.pause();
    }

    // ---- views ----

    function test_GetVoterStats() public {
        vm.prank(alice);
        game.vote(true);
        (uint256 p, uint256 s, uint256 last, uint256 total) = game.getVoterStats(alice);
        assertEq(p, 0);
        assertEq(s, 1);
        assertEq(last, _day());
        assertEq(total, 1);
    }
}
