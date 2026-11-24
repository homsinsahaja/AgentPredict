// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {AgentPredict} from "../src/AgentPredict.sol";

/// @notice Deploy AgentPredict to BSC mainnet (chain id 56).
/// @dev Run with: forge script script/Deploy.s.sol --rpc-url bsc --broadcast
///      The deployer key is supplied on the command line; never commit one.
///      After deploy: verify on BscScan + Sourcify (see README.md).
contract Deploy is Script {
    address public constant AGENT_ID_REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    address public constant CHAINLINK_BTC_USD = 0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf;

    function run() external returns (AgentPredict) {
        vm.startBroadcast();
        AgentPredict game = new AgentPredict(AGENT_ID_REGISTRY, CHAINLINK_BTC_USD);
        vm.stopBroadcast();
        return game;
    }
}
