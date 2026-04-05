// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/PliqTypes.sol";

interface IReputationAccumulator {
    // Write
    function recordAction(address user, PliqTypes.ActionType action, uint128 value) external;
    function mintReputationSBT(address user) external returns (uint256 tokenId);
    function updateSBT(uint256 tokenId) external;
    function commitMerkleRoot(bytes32 root, uint64 timestamp) external;

    // Admin
    function setActionWeight(PliqTypes.ActionType action, int128 weight) external;
    function setDecayHalfLife(uint64 halfLifeDays) external;

    // Read
    function calculateScore(address user) external view returns (int256);
    function getActionHistory(address user) external view returns (PliqTypes.ReputationAction[] memory);
    function getLatestMerkleRoot() external view returns (bytes32 root, uint64 timestamp);
    function verifyMerkleProof(bytes32[] calldata proof, bytes32 leaf, bytes32 root) external pure returns (bool);
    function getTokenIdByUser(address user) external view returns (uint256);

    // ERC-5192
    function locked(uint256 tokenId) external view returns (bool);

    // Events
    event ActionRecorded(address indexed user, PliqTypes.ActionType action, uint128 value);
    event ScoreUpdated(address indexed user, int256 newScore);
    event SBTMinted(uint256 indexed tokenId, address indexed user, int256 score);
    event SBTUpdated(uint256 indexed tokenId, int256 newScore);
    event MerkleRootCommitted(bytes32 indexed root, uint64 timestamp);
}
