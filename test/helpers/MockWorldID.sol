// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title MockWorldID - Mock World ID router for testing
contract MockWorldID {
    bool public shouldRevert;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function verifyProof(
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256[8] calldata
    ) external view {
        if (shouldRevert) {
            revert("MockWorldID: invalid proof");
        }
    }
}
