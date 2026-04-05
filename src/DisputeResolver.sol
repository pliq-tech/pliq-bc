// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./libraries/PliqTypes.sol";
import "./libraries/PliqErrors.sol";

/// @title DisputeResolver - Dispute lifecycle with evidence, juror voting, appeal
contract DisputeResolver is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant JUROR_ROLE = keccak256("JUROR_ROLE");

    uint64 public constant EVIDENCE_PERIOD = 3 days;
    uint64 public constant VOTING_PERIOD = 5 days;
    uint64 public constant APPEAL_WINDOW = 2 days;

    mapping(uint256 => PliqTypes.Dispute) private _disputes;
    mapping(uint256 => mapping(address => PliqTypes.VoteChoice)) private _votes;
    mapping(uint256 => bytes32[]) private _evidenceHashes;
    uint256 public disputeCount;

    event DisputeFiled(uint256 indexed disputeId, uint256 indexed agreementId, address indexed initiator, address respondent);
    event EvidenceSubmitted(uint256 indexed disputeId, bytes32 evidenceHash);
    event VotingStarted(uint256 indexed disputeId);
    event VoteCast(uint256 indexed disputeId, address indexed juror, PliqTypes.VoteChoice choice);
    event DisputeResolved(uint256 indexed disputeId, PliqTypes.VoteChoice outcome);
    event DisputeAppealed(uint256 indexed disputeId);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    /// @notice File a new dispute for an agreement
    function fileDispute(uint256 agreementId, address respondent, string calldata reason) external whenNotPaused returns (uint256) {
        if (respondent == address(0)) revert PliqErrors.ZeroAddress();
        disputeCount++;
        uint64 now_ = uint64(block.timestamp);
        _disputes[disputeCount] = PliqTypes.Dispute({
            agreementId: agreementId,
            initiator: msg.sender,
            respondent: respondent,
            reason: reason,
            status: PliqTypes.DisputeStatus.Filed,
            createdAt: now_,
            evidenceDeadline: now_ + EVIDENCE_PERIOD,
            votingDeadline: 0,
            resolvedAt: 0,
            totalVotesFor: 0,
            totalVotesAgainst: 0
        });
        emit DisputeFiled(disputeCount, agreementId, msg.sender, respondent);
        return disputeCount;
    }

    /// @notice Submit evidence hash (initiator or respondent only, before deadline)
    function submitEvidence(uint256 disputeId, bytes32 evidenceHash) external whenNotPaused {
        PliqTypes.Dispute storage d = _disputes[disputeId];
        if (msg.sender != d.initiator && msg.sender != d.respondent) revert PliqErrors.NotDisputeParty(msg.sender);
        if (block.timestamp > d.evidenceDeadline) revert PliqErrors.EvidenceDeadlinePassed(d.evidenceDeadline);
        _evidenceHashes[disputeId].push(evidenceHash);
        emit EvidenceSubmitted(disputeId, evidenceHash);
    }

    /// @notice Transition dispute to voting phase (operator triggers after evidence period)
    function startVoting(uint256 disputeId) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        PliqTypes.Dispute storage d = _disputes[disputeId];
        d.status = PliqTypes.DisputeStatus.Voting;
        d.votingDeadline = uint64(block.timestamp) + VOTING_PERIOD;
        emit VotingStarted(disputeId);
    }

    /// @notice Cast a vote (jurors only)
    function castVote(uint256 disputeId, PliqTypes.VoteChoice choice) external onlyRole(JUROR_ROLE) whenNotPaused {
        PliqTypes.Dispute storage d = _disputes[disputeId];
        if (d.status != PliqTypes.DisputeStatus.Voting) revert PliqErrors.NotDisputeParty(msg.sender);
        if (block.timestamp > d.votingDeadline) revert PliqErrors.EvidenceDeadlinePassed(d.votingDeadline);
        if (_votes[disputeId][msg.sender] != PliqTypes.VoteChoice.None) revert PliqErrors.AlreadyVoted(msg.sender);
        _votes[disputeId][msg.sender] = choice;
        if (choice == PliqTypes.VoteChoice.ForInitiator) { d.totalVotesFor++; }
        else if (choice == PliqTypes.VoteChoice.ForRespondent) { d.totalVotesAgainst++; }
        emit VoteCast(disputeId, msg.sender, choice);
    }

    /// @notice Resolve the dispute based on votes (operator triggers after voting period)
    function resolveDispute(uint256 disputeId) external onlyRole(OPERATOR_ROLE) nonReentrant whenNotPaused {
        PliqTypes.Dispute storage d = _disputes[disputeId];
        d.status = PliqTypes.DisputeStatus.Resolved;
        d.resolvedAt = uint64(block.timestamp);
        PliqTypes.VoteChoice outcome = d.totalVotesFor >= d.totalVotesAgainst ? PliqTypes.VoteChoice.ForInitiator : PliqTypes.VoteChoice.ForRespondent;
        emit DisputeResolved(disputeId, outcome);
    }

    /// @notice Appeal a resolved dispute (within appeal window)
    function appealDispute(uint256 disputeId) external whenNotPaused {
        PliqTypes.Dispute storage d = _disputes[disputeId];
        if (msg.sender != d.initiator && msg.sender != d.respondent) revert PliqErrors.NotDisputeParty(msg.sender);
        if (d.status != PliqTypes.DisputeStatus.Resolved) revert PliqErrors.NotDisputeParty(msg.sender);
        if (block.timestamp > d.resolvedAt + APPEAL_WINDOW) revert PliqErrors.AppealWindowExpired();
        d.status = PliqTypes.DisputeStatus.Appealed;
        emit DisputeAppealed(disputeId);
    }

    function getDisputeById(uint256 id) external view returns (PliqTypes.Dispute memory) { return _disputes[id]; }
    function getEvidence(uint256 disputeId) external view returns (bytes32[] memory) { return _evidenceHashes[disputeId]; }
    function getVote(uint256 disputeId, address juror) external view returns (PliqTypes.VoteChoice) { return _votes[disputeId][juror]; }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
