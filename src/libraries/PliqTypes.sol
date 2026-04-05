// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library PliqTypes {
    enum VerificationLevel {
        None,
        Device,
        Orb,
        Passport
    }

    enum ListingStatus {
        Active,
        Paused,
        Rented,
        Removed
    }

    enum ApplicationStatus {
        Pending,
        Accepted,
        Rejected,
        Withdrawn
    }

    enum AgreementStatus {
        Created,
        DepositPaid,
        Active,
        MoveInComplete,
        MoveOutInitiated,
        MoveOutComplete,
        Terminated,
        Disputed
    }

    enum StakeType {
        Listing,
        Visit,
        Rent
    }

    enum StakeStatus {
        Active,
        Released,
        Slashed,
        PartiallySlashed
    }

    enum ActionType {
        RentPaidOnTime,
        RentPaidLate,
        PositiveReview,
        NegativeReview,
        DisputeWon,
        DisputeLost,
        StakeSlashed,
        SuccessfulMoveOut,
        ListingVerified,
        VisitCompleted
    }

    enum DisputeStatus {
        Filed,
        EvidenceCollection,
        Voting,
        Resolved,
        Appealed
    }

    enum PaymentStatus {
        Completed,
        Failed,
        Pending
    }

    enum BridgeStatus {
        Initiated,
        Attested,
        Completed,
        Failed
    }

    struct User {
        address userAddress;
        uint256 nullifierHash;
        VerificationLevel verificationLevel;
        uint64 registrationTimestamp;
        bool isActive;
    }

    struct Listing {
        address owner;
        bytes32 listingHash;
        uint128 deposit;
        uint128 monthlyRent;
        string metadataURI;
        ListingStatus status;
        uint64 createdAt;
    }

    struct Application {
        address applicant;
        uint256 listingId;
        ApplicationStatus status;
        uint64 appliedAt;
    }

    struct Agreement {
        address landlord;
        address tenant;
        uint256 listingId;
        bytes32 leaseHash;
        uint64 startDate;
        uint64 endDate;
        uint128 deposit;
        uint128 monthlyRent;
        AgreementStatus status;
        bytes32 checkInReportHash;
        bytes32 checkOutReportHash;
        bool landlordConfirmedMoveIn;
        bool tenantConfirmedMoveIn;
        uint64 createdAt;
    }

    struct Stake {
        address staker;
        StakeType stakeType;
        uint128 amount;
        uint256 referenceId;
        StakeStatus status;
        uint64 createdAt;
    }

    struct ReputationAction {
        ActionType actionType;
        uint128 value;
        uint64 timestamp;
    }

    struct Dispute {
        uint256 agreementId;
        address initiator;
        address respondent;
        string reason;
        DisputeStatus status;
        uint64 createdAt;
        uint64 evidenceDeadline;
        uint64 votingDeadline;
        uint64 resolvedAt;
        uint256 totalVotesFor;
        uint256 totalVotesAgainst;
    }

    struct Evidence {
        address submitter;
        bytes32 evidenceHash;
        string evidenceURI;
        uint64 submittedAt;
    }

    struct Payment {
        uint256 agreementId;
        uint128 amount;
        address token;
        PaymentStatus status;
        uint64 timestamp;
    }

    struct RecurringSchedule {
        uint256 agreementId;
        uint128 amount;
        address token;
        uint32 intervalDays;
        uint64 nextPaymentDate;
        bool active;
    }
}
