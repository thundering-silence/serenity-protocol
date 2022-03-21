// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

contract MockAggregatorV3 {
    uint internal _answer;

    constructor() {
        _answer = 1e8;
    }

    function setAnswer(uint answer_) public {
        _answer = answer_;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        roundId = 100;
        answer = int256(_answer);
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = roundId;
    }
}
