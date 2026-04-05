// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./libraries/PliqTypes.sol";
import "./libraries/PliqErrors.sol";

/// @title ReputationAccumulator - Soulbound ERC721 reputation with score decay and Merkle proof
/// @notice Implements ERC-5192 (Minimal Soulbound), on-chain score with time-weighted decay
contract ReputationAccumulator is ERC721, AccessControl, Pausable {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 private constant DECAY_PERIOD = 90 days;
    uint128 private constant DECAY_BPS = 500; // 5% per period
    uint128 private constant BPS_BASE = 10_000;

    mapping(address => uint256) private _tokenOfUser;
    mapping(uint256 => PliqTypes.ReputationAction[]) private _actions;
    mapping(uint256 => uint128) private _baseScore;
    mapping(uint256 => uint64) private _lastUpdate;

    uint256 public tokenCount;
    bytes32 public merkleRoot;
    uint64 public merkleUpdatedAt;

    event ReputationMinted(address indexed user, uint256 indexed tokenId);
    event ActionRecorded(uint256 indexed tokenId, PliqTypes.ActionType actionType, uint128 value);
    event ScoreUpdated(uint256 indexed tokenId, uint128 newScore);
    event MerkleRootUpdated(bytes32 newRoot, uint64 timestamp);

    /// @dev ERC-5192 event
    event Locked(uint256 indexed tokenId);

    constructor() ERC721("Pliq Reputation", "PLIQ-REP") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    /// @notice Mint a soulbound reputation token for a user
    function mintReputation(address user) external onlyRole(OPERATOR_ROLE) whenNotPaused returns (uint256) {
        if (_tokenOfUser[user] != 0) revert PliqErrors.SBTAlreadyMinted(user);
        tokenCount++;
        _safeMint(user, tokenCount);
        _tokenOfUser[user] = tokenCount;
        _baseScore[tokenCount] = 500; // Start at 500/1000
        _lastUpdate[tokenCount] = uint64(block.timestamp);
        emit ReputationMinted(user, tokenCount);
        emit Locked(tokenCount);
        return tokenCount;
    }

    /// @notice Record a reputation action
    function recordAction(uint256 tokenId, PliqTypes.ActionType actionType, uint128 value) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        if (ownerOf(tokenId) == address(0)) revert PliqErrors.ZeroAddress();
        _applyDecay(tokenId);
        _actions[tokenId].push(PliqTypes.ReputationAction({ actionType: actionType, value: value, timestamp: uint64(block.timestamp) }));
        _applyAction(tokenId, actionType, value);
        emit ActionRecorded(tokenId, actionType, value);
    }

    /// @notice Get the current score with decay applied
    function getScore(uint256 tokenId) external view returns (uint128) {
        return _calculateDecayedScore(tokenId);
    }

    /// @notice Get all actions for a token
    function getActions(uint256 tokenId) external view returns (PliqTypes.ReputationAction[] memory) {
        return _actions[tokenId];
    }

    /// @notice Get token ID for a user
    function tokenOfUser(address user) external view returns (uint256) {
        return _tokenOfUser[user];
    }

    /// @notice Update Merkle root (operator publishes off-chain computed tree)
    function updateMerkleRoot(bytes32 newRoot) external onlyRole(OPERATOR_ROLE) {
        merkleRoot = newRoot;
        merkleUpdatedAt = uint64(block.timestamp);
        emit MerkleRootUpdated(newRoot, merkleUpdatedAt);
    }

    /// @notice Verify a Merkle proof for a leaf
    function verifyProof(bytes32[] calldata proof, bytes32 leaf) external view returns (bool) {
        bytes32 computed = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 sibling = proof[i];
            computed = computed <= sibling ? keccak256(abi.encodePacked(computed, sibling)) : keccak256(abi.encodePacked(sibling, computed));
        }
        return computed == merkleRoot;
    }

    /// @dev ERC-5192: All tokens are permanently locked (soulbound)
    function locked(uint256 tokenId) external view returns (bool) {
        ownerOf(tokenId); // reverts if token doesn't exist
        return true;
    }

    /// @dev Block all transfers (soulbound)
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) revert PliqErrors.SoulboundTransferBlocked();
        return super._update(to, tokenId, auth);
    }

    /// @dev Apply time-based decay to stored score
    function _applyDecay(uint256 tokenId) internal {
        uint128 decayed = _calculateDecayedScore(tokenId);
        _baseScore[tokenId] = decayed;
        _lastUpdate[tokenId] = uint64(block.timestamp);
        emit ScoreUpdated(tokenId, decayed);
    }

    /// @dev Calculate score with decay without modifying state
    function _calculateDecayedScore(uint256 tokenId) internal view returns (uint128) {
        uint128 score = _baseScore[tokenId];
        uint64 elapsed = uint64(block.timestamp) - _lastUpdate[tokenId];
        uint256 periods = elapsed / DECAY_PERIOD;
        for (uint256 i = 0; i < periods && score > 0; i++) {
            score = score - (score * DECAY_BPS / BPS_BASE);
        }
        return score;
    }

    /// @dev Apply score change based on action type
    function _applyAction(uint256 tokenId, PliqTypes.ActionType actionType, uint128 value) internal {
        uint128 score = _baseScore[tokenId];
        if (actionType == PliqTypes.ActionType.RentPaidOnTime || actionType == PliqTypes.ActionType.PositiveReview || actionType == PliqTypes.ActionType.DisputeWon || actionType == PliqTypes.ActionType.SuccessfulMoveOut) {
            score = score + value > 1000 ? 1000 : score + value;
        } else {
            score = value > score ? 0 : score - value;
        }
        _baseScore[tokenId] = score;
        emit ScoreUpdated(tokenId, score);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return interfaceId == 0xb45a3c0e || super.supportsInterface(interfaceId); // ERC-5192 interface ID
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
