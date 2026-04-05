// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./libraries/PliqTypes.sol";
import "./libraries/PliqErrors.sol";
import "./interfaces/IPliqRegistry.sol";

/// @title ReputationAccumulator - Soulbound ERC721 reputation with score decay and Merkle proof
/// @notice Implements ERC-5192 (Minimal Soulbound), on-chain score with time-weighted decay, Merkle root commits
contract ReputationAccumulator is ERC721, AccessControl, Pausable {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    IPliqRegistry public registry;

    // Score decay: half-life in seconds (default 90 days)
    uint64 public decayHalfLife = 90 days;

    // Action weights: positive or negative impact per action type
    mapping(PliqTypes.ActionType => int128) private _actionWeights;

    // User -> tokenId mapping
    mapping(address => uint256) private _userTokens;

    // User -> action history
    mapping(address => PliqTypes.ReputationAction[]) private _userActions;

    // Merkle root storage
    bytes32 public latestMerkleRoot;
    uint64 public merkleRootTimestamp;

    uint256 public tokenCount;

    // Events
    event ActionRecorded(address indexed user, PliqTypes.ActionType action, uint128 value);
    event ScoreUpdated(address indexed user, int256 newScore);
    event SBTMinted(uint256 indexed tokenId, address indexed user, int256 score);
    event SBTUpdated(uint256 indexed tokenId, int256 newScore);
    event MerkleRootCommitted(bytes32 indexed root, uint64 timestamp);

    /// @dev ERC-5192 event
    event Locked(uint256 indexed tokenId);

    constructor(address _registry) ERC721("Pliq Reputation", "PREPSBT") {
        if (_registry == address(0)) revert PliqErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        registry = IPliqRegistry(_registry);

        // Default action weights
        _actionWeights[PliqTypes.ActionType.RentPaidOnTime] = 10;
        _actionWeights[PliqTypes.ActionType.RentPaidLate] = -5;
        _actionWeights[PliqTypes.ActionType.PositiveReview] = 15;
        _actionWeights[PliqTypes.ActionType.NegativeReview] = -10;
        _actionWeights[PliqTypes.ActionType.DisputeWon] = 20;
        _actionWeights[PliqTypes.ActionType.DisputeLost] = -20;
        _actionWeights[PliqTypes.ActionType.StakeSlashed] = -30;
        _actionWeights[PliqTypes.ActionType.SuccessfulMoveOut] = 25;
        _actionWeights[PliqTypes.ActionType.ListingVerified] = 10;
        _actionWeights[PliqTypes.ActionType.VisitCompleted] = 5;
    }

    /// @notice Record a reputation-affecting action for a user
    function recordAction(address user, PliqTypes.ActionType action, uint128 value) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        if (user == address(0)) revert PliqErrors.ZeroAddress();

        _userActions[user].push(PliqTypes.ReputationAction({
            actionType: action,
            value: value,
            timestamp: uint64(block.timestamp)
        }));

        int256 score = calculateScore(user);
        emit ActionRecorded(user, action, value);
        emit ScoreUpdated(user, score);
    }

    /// @notice Calculate the current reputation score for a user with decay
    function calculateScore(address user) public view returns (int256) {
        PliqTypes.ReputationAction[] storage actions = _userActions[user];
        int256 totalScore = 0;

        for (uint256 i = 0; i < actions.length; i++) {
            int128 weight = _actionWeights[actions[i].actionType];
            uint64 elapsed = uint64(block.timestamp) - actions[i].timestamp;

            // Apply exponential decay: contribution = weight * value * 2^(-(elapsed / halfLife))
            // Approximation: reduce by half for each halfLife period
            int256 contribution = int256(weight) * int256(uint256(actions[i].value));
            uint256 periods = uint256(elapsed) / uint256(decayHalfLife);

            // Apply decay: divide by 2^periods (cap at 64 to prevent excessive computation)
            if (periods < 64) {
                contribution = contribution / int256(uint256(1) << periods);
            } else {
                contribution = 0;
            }

            totalScore += contribution;
        }

        return totalScore;
    }

    /// @notice Mint a soulbound reputation token for a user
    function mintReputationSBT(address user) external onlyRole(OPERATOR_ROLE) whenNotPaused returns (uint256) {
        if (user == address(0)) revert PliqErrors.ZeroAddress();
        if (_userTokens[user] != 0) revert PliqErrors.SBTAlreadyMinted(user);

        tokenCount++;
        _safeMint(user, tokenCount);
        _userTokens[user] = tokenCount;

        int256 score = calculateScore(user);
        emit SBTMinted(tokenCount, user, score);
        emit Locked(tokenCount);

        return tokenCount;
    }

    /// @notice Update the score snapshot in an existing SBT
    function updateSBT(uint256 tokenId) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        address owner = ownerOf(tokenId);
        int256 score = calculateScore(owner);
        emit SBTUpdated(tokenId, score);
    }

    /// @notice Commit a Merkle root of all reputation data (ORACLE_ROLE only)
    function commitMerkleRoot(bytes32 root, uint64 timestamp) external onlyRole(ORACLE_ROLE) {
        latestMerkleRoot = root;
        merkleRootTimestamp = timestamp;
        emit MerkleRootCommitted(root, timestamp);
    }

    /// @notice Verify a Merkle proof against a given root
    function verifyMerkleProof(bytes32[] calldata proof, bytes32 leaf, bytes32 root) external pure returns (bool) {
        return MerkleProof.verify(proof, root, leaf);
    }

    // Admin functions
    function setActionWeight(PliqTypes.ActionType action, int128 weight) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _actionWeights[action] = weight;
    }

    function setDecayHalfLife(uint64 halfLifeDays) external onlyRole(DEFAULT_ADMIN_ROLE) {
        decayHalfLife = halfLifeDays * 1 days;
    }

    // View functions
    function getActionHistory(address user) external view returns (PliqTypes.ReputationAction[] memory) {
        return _userActions[user];
    }

    function getLatestMerkleRoot() external view returns (bytes32 root, uint64 timestamp) {
        return (latestMerkleRoot, merkleRootTimestamp);
    }

    function getTokenIdByUser(address user) external view returns (uint256) { return _userTokens[user]; }
    function getScore(address user) external view returns (int256) { return calculateScore(user); }

    /// @dev ERC-5192: All tokens are permanently locked (soulbound)
    function locked(uint256 tokenId) external view returns (bool) {
        ownerOf(tokenId); // reverts if token doesn't exist
        return true;
    }

    /// @dev Block all transfers (soulbound) - only mint allowed
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) revert PliqErrors.SoulboundTransferBlocked();
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return interfaceId == 0xb45a3c0e || super.supportsInterface(interfaceId); // ERC-5192
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
