// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./libraries/PliqTypes.sol";
import "./libraries/PliqErrors.sol";
import "./interfaces/IRentalAgreement.sol";
import "./interfaces/IStakingManager.sol";
import "./interfaces/IReputationAccumulator.sol";

/// @title DisputeResolver - Dispute lifecycle with evidence, juror voting, slashing, and appeals
/// @notice Manages disputes through evidence collection, juror selection, voting, resolution, and appeals
contract DisputeResolver is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    IRentalAgreement public rentalAgreement;
    IStakingManager public stakingManager;
    IReputationAccumulator public reputationAccumulator;

    // Configurable parameters
    uint32 public evidenceDeadlineDays = 7;
    uint32 public votingDeadlineDays = 5;
    uint32 public appealWindowDays = 2;
    uint32 public jurorCount = 3;
    int256 public minJurorReputation = 50;
    uint32 public appealStakeMultiplier = 2;

    // Storage
    mapping(uint256 => PliqTypes.Dispute) private _disputes;
    mapping(uint256 => PliqTypes.Evidence[]) private _evidence;
    mapping(uint256 => address[]) private _jurors;
    mapping(uint256 => mapping(address => bool)) private _jurorSelected;
    mapping(uint256 => mapping(address => bool)) private _hasVoted;
    mapping(uint256 => uint256[]) private _agreementDisputes;
    uint256 public disputeCount;

    // Events
    event DisputeRaised(uint256 indexed disputeId, uint256 indexed agreementId, address indexed initiator);
    event EvidenceSubmitted(uint256 indexed disputeId, address indexed submitter, bytes32 evidenceHash);
    event JurorsSelected(uint256 indexed disputeId, address[] jurors);
    event VoteCast(uint256 indexed disputeId, address indexed juror, bool favorInitiator);
    event DisputeResolved(uint256 indexed disputeId, bool favorInitiator, uint256 votesFor, uint256 votesAgainst);
    event DisputeAppealed(uint256 indexed disputeId, address indexed appellant);

    constructor(
        address _rentalAgreement,
        address _stakingManager,
        address _reputationAccumulator
    ) {
        if (_rentalAgreement == address(0) || _stakingManager == address(0) || _reputationAccumulator == address(0)) {
            revert PliqErrors.ZeroAddress();
        }
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);

        rentalAgreement = IRentalAgreement(_rentalAgreement);
        stakingManager = IStakingManager(_stakingManager);
        reputationAccumulator = IReputationAccumulator(_reputationAccumulator);
    }

    /// @notice Raise a dispute for an agreement
    function raiseDispute(
        uint256 agreementId,
        string calldata reason,
        bytes32 evidenceHash
    ) external whenNotPaused returns (uint256) {
        PliqTypes.Agreement memory agreement = rentalAgreement.getAgreementById(agreementId);
        if (msg.sender != agreement.landlord && msg.sender != agreement.tenant) {
            revert PliqErrors.NotAgreementParty(msg.sender);
        }

        address respondent = msg.sender == agreement.landlord ? agreement.tenant : agreement.landlord;

        disputeCount++;
        uint64 now_ = uint64(block.timestamp);
        _disputes[disputeCount] = PliqTypes.Dispute({
            agreementId: agreementId,
            initiator: msg.sender,
            respondent: respondent,
            reason: reason,
            status: PliqTypes.DisputeStatus.EvidenceCollection,
            createdAt: now_,
            evidenceDeadline: now_ + uint64(evidenceDeadlineDays) * 1 days,
            votingDeadline: 0,
            resolvedAt: 0,
            totalVotesFor: 0,
            totalVotesAgainst: 0
        });

        _agreementDisputes[agreementId].push(disputeCount);

        // Store initial evidence
        if (evidenceHash != bytes32(0)) {
            _evidence[disputeCount].push(PliqTypes.Evidence({
                submitter: msg.sender,
                evidenceHash: evidenceHash,
                evidenceURI: "",
                submittedAt: now_
            }));
        }

        emit DisputeRaised(disputeCount, agreementId, msg.sender);
        return disputeCount;
    }

    /// @notice Submit evidence (dispute parties only, before deadline)
    function submitEvidence(
        uint256 disputeId,
        bytes32 evidenceHash,
        string calldata evidenceURI
    ) external whenNotPaused {
        PliqTypes.Dispute storage d = _disputes[disputeId];
        if (d.createdAt == 0) revert PliqErrors.DisputeNotFound(disputeId);
        if (msg.sender != d.initiator && msg.sender != d.respondent) revert PliqErrors.NotDisputeParty(msg.sender);
        if (d.status != PliqTypes.DisputeStatus.EvidenceCollection) {
            revert PliqErrors.InvalidDisputeStatus(uint8(d.status), uint8(PliqTypes.DisputeStatus.EvidenceCollection));
        }
        if (block.timestamp > d.evidenceDeadline) revert PliqErrors.EvidenceDeadlinePassed(d.evidenceDeadline);

        _evidence[disputeId].push(PliqTypes.Evidence({
            submitter: msg.sender,
            evidenceHash: evidenceHash,
            evidenceURI: evidenceURI,
            submittedAt: uint64(block.timestamp)
        }));

        emit EvidenceSubmitted(disputeId, msg.sender, evidenceHash);
    }

    /// @notice Select jurors for a dispute (after evidence deadline)
    function selectJurors(uint256 disputeId) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        PliqTypes.Dispute storage d = _disputes[disputeId];
        if (d.createdAt == 0) revert PliqErrors.DisputeNotFound(disputeId);
        if (d.status != PliqTypes.DisputeStatus.EvidenceCollection) {
            revert PliqErrors.InvalidDisputeStatus(uint8(d.status), uint8(PliqTypes.DisputeStatus.EvidenceCollection));
        }

        // Use block hash for pseudo-randomness (MVP approach)
        // In production, this would use Chainlink VRF
        bytes32 seed = keccak256(abi.encodePacked(blockhash(block.number - 1), disputeId, block.timestamp));

        address[] memory selectedJurors = new address[](jurorCount);
        uint256 selected = 0;

        // For MVP: use deterministic addresses from seed
        // In production: query reputation holders above threshold
        for (uint256 i = 0; selected < jurorCount && i < 100; i++) {
            address candidate = address(uint160(uint256(keccak256(abi.encodePacked(seed, i)))));
            if (candidate != d.initiator && candidate != d.respondent && !_jurorSelected[disputeId][candidate]) {
                selectedJurors[selected] = candidate;
                _jurorSelected[disputeId][candidate] = true;
                selected++;
            }
        }

        _jurors[disputeId] = selectedJurors;
        d.status = PliqTypes.DisputeStatus.Voting;
        d.votingDeadline = uint64(block.timestamp) + uint64(votingDeadlineDays) * 1 days;

        emit JurorsSelected(disputeId, selectedJurors);
    }

    /// @notice Cast a vote (selected jurors only)
    function castVote(uint256 disputeId, bool favorInitiator) external whenNotPaused {
        PliqTypes.Dispute storage d = _disputes[disputeId];
        if (d.status != PliqTypes.DisputeStatus.Voting) {
            revert PliqErrors.InvalidDisputeStatus(uint8(d.status), uint8(PliqTypes.DisputeStatus.Voting));
        }
        if (block.timestamp > d.votingDeadline) revert PliqErrors.VotingDeadlinePassed(d.votingDeadline);
        if (!_jurorSelected[disputeId][msg.sender]) revert PliqErrors.NotSelectedJuror(msg.sender);
        if (_hasVoted[disputeId][msg.sender]) revert PliqErrors.AlreadyVoted(msg.sender);

        _hasVoted[disputeId][msg.sender] = true;

        if (favorInitiator) {
            d.totalVotesFor++;
        } else {
            d.totalVotesAgainst++;
        }

        emit VoteCast(disputeId, msg.sender, favorInitiator);
    }

    /// @notice Resolve the dispute based on votes
    function resolveDispute(uint256 disputeId) external onlyRole(OPERATOR_ROLE) nonReentrant whenNotPaused {
        PliqTypes.Dispute storage d = _disputes[disputeId];
        if (d.status != PliqTypes.DisputeStatus.Voting) {
            revert PliqErrors.InvalidDisputeStatus(uint8(d.status), uint8(PliqTypes.DisputeStatus.Voting));
        }

        // Allow early resolution if all votes cast, otherwise require deadline passed
        uint256 totalVotes = d.totalVotesFor + d.totalVotesAgainst;
        if (totalVotes < jurorCount && block.timestamp <= d.votingDeadline) {
            revert PliqErrors.VotingNotEnded(d.votingDeadline);
        }

        bool initiatorWins = d.totalVotesFor >= d.totalVotesAgainst;

        d.status = PliqTypes.DisputeStatus.Resolved;
        d.resolvedAt = uint64(block.timestamp);

        emit DisputeResolved(disputeId, initiatorWins, d.totalVotesFor, d.totalVotesAgainst);
    }

    /// @notice Appeal a resolved dispute (within appeal window)
    function appeal(uint256 disputeId) external whenNotPaused {
        PliqTypes.Dispute storage d = _disputes[disputeId];
        if (d.status != PliqTypes.DisputeStatus.Resolved) {
            revert PliqErrors.InvalidDisputeStatus(uint8(d.status), uint8(PliqTypes.DisputeStatus.Resolved));
        }
        if (msg.sender != d.initiator && msg.sender != d.respondent) revert PliqErrors.NotDisputeParty(msg.sender);
        if (block.timestamp > d.resolvedAt + uint64(appealWindowDays) * 1 days) revert PliqErrors.AppealWindowExpired();

        d.status = PliqTypes.DisputeStatus.Appealed;
        emit DisputeAppealed(disputeId, msg.sender);
    }

    // Admin functions
    function setEvidenceDeadlineDays(uint32 numDays) external onlyRole(DEFAULT_ADMIN_ROLE) { evidenceDeadlineDays = numDays; }
    function setVotingDeadlineDays(uint32 numDays) external onlyRole(DEFAULT_ADMIN_ROLE) { votingDeadlineDays = numDays; }
    function setAppealWindowDays(uint32 numDays) external onlyRole(DEFAULT_ADMIN_ROLE) { appealWindowDays = numDays; }
    function setJurorCount(uint32 count) external onlyRole(DEFAULT_ADMIN_ROLE) { jurorCount = count; }
    function setMinJurorReputation(int256 minScore) external onlyRole(DEFAULT_ADMIN_ROLE) { minJurorReputation = minScore; }
    function setAppealStakeMultiplier(uint32 multiplier) external onlyRole(DEFAULT_ADMIN_ROLE) { appealStakeMultiplier = multiplier; }

    // View functions
    function getDisputeById(uint256 id) external view returns (PliqTypes.Dispute memory) { return _disputes[id]; }
    function getDisputesByAgreement(uint256 agreementId) external view returns (uint256[] memory) { return _agreementDisputes[agreementId]; }
    function getJurors(uint256 disputeId) external view returns (address[] memory) { return _jurors[disputeId]; }
    function getEvidence(uint256 disputeId) external view returns (PliqTypes.Evidence[] memory) { return _evidence[disputeId]; }
    function hasVoted(uint256 disputeId, address juror) external view returns (bool) { return _hasVoted[disputeId][juror]; }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
