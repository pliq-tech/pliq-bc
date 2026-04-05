// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/PliqTypes.sol";

interface IDisputeResolver {
    // Write
    function raiseDispute(
        uint256 agreementId,
        string calldata reason,
        bytes32 evidenceHash
    ) external returns (uint256 disputeId);

    function submitEvidence(
        uint256 disputeId,
        bytes32 evidenceHash,
        string calldata evidenceURI
    ) external;

    function selectJurors(uint256 disputeId) external;
    function castVote(uint256 disputeId, bool favorInitiator) external;
    function resolveDispute(uint256 disputeId) external;
    function appeal(uint256 disputeId) external;

    // Admin
    function setEvidenceDeadlineDays(uint32 numDays) external;
    function setVotingDeadlineDays(uint32 numDays) external;
    function setAppealWindowDays(uint32 numDays) external;
    function setJurorCount(uint32 count) external;
    function setMinJurorReputation(int256 minScore) external;
    function setAppealStakeMultiplier(uint32 multiplier) external;

    // Read
    function getDisputeById(uint256 disputeId) external view returns (PliqTypes.Dispute memory);
    function getDisputesByAgreement(uint256 agreementId) external view returns (uint256[] memory);
    function getJurors(uint256 disputeId) external view returns (address[] memory);
    function getEvidence(uint256 disputeId) external view returns (PliqTypes.Evidence[] memory);
    function hasVoted(uint256 disputeId, address juror) external view returns (bool);

    // Events
    event DisputeRaised(uint256 indexed disputeId, uint256 indexed agreementId, address indexed initiator);
    event EvidenceSubmitted(uint256 indexed disputeId, address indexed submitter, bytes32 evidenceHash);
    event JurorsSelected(uint256 indexed disputeId, address[] jurors);
    event VoteCast(uint256 indexed disputeId, address indexed juror, bool favorInitiator);
    event DisputeResolved(uint256 indexed disputeId, bool favorInitiator, uint256 votesFor, uint256 votesAgainst);
    event DisputeAppealed(uint256 indexed disputeId, address indexed appellant);
}
