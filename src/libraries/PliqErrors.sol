// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library PliqErrors {
    // Registry
    error AlreadyRegistered(uint256 nullifierHash);
    error NotRegistered(address user);
    error InsufficientVerification(uint8 required, uint8 actual);
    error InvalidWorldIDProof();
    error ListingNotFound(uint256 listingId);
    error ApplicationNotFound(uint256 applicationId);
    error InvalidListingStatus(uint8 current, uint8 expected);
    error InvalidApplicationStatus(uint8 current, uint8 expected);
    error NotListingOwner(address caller, address owner);
    error NotApplicant(address caller, address applicant);
    error ListingNotActive(uint256 listingId);
    error AlreadyApplied(address applicant, uint256 listingId);

    // Agreement
    error AgreementNotFound(uint256 agreementId);
    error InvalidAgreementStatus(uint8 current, uint8 expected);
    error NotAgreementParty(address caller);
    error MoveInNotConfirmedByBoth();
    error DepositAlreadyPaid();
    error DeductionExceedsDeposit(uint128 deduction, uint128 deposit);
    error NotLandlord(address caller, address landlord);
    error NotTenant(address caller, address tenant);

    // Staking
    error StakeNotFound(uint256 stakeId);
    error InsufficientStakeAmount(uint128 amount, uint128 minimum);
    error StakeAlreadyReleased(uint256 stakeId);
    error SlashExceedsStake(uint128 slashAmount, uint128 stakeAmount);
    error StakeNotActive(uint256 stakeId);

    // Reputation
    error SBTAlreadyMinted(address user);
    error SBTNotFound(uint256 tokenId);
    error SoulboundTransferBlocked();

    // Payments
    error TokenNotSupported(address token);
    error InsufficientAllowance(uint256 required, uint256 actual);
    error PaymentFailed(uint256 agreementId, string reason);
    error RecurringNotDue(uint256 scheduleId, uint64 nextDate);
    error FeeTooHigh(uint16 fee, uint16 max);
    error ScheduleNotActive(uint256 scheduleId);

    // Disputes
    error DisputeNotFound(uint256 disputeId);
    error InvalidDisputeStatus(uint8 current, uint8 expected);
    error EvidenceDeadlinePassed(uint64 deadline);
    error VotingDeadlinePassed(uint64 deadline);
    error VotingNotEnded(uint64 deadline);
    error NotSelectedJuror(address caller);
    error AlreadyVoted(address juror);
    error AppealWindowExpired();
    error InsufficientAppealStake();
    error NotDisputeParty(address caller);

    // General
    error ZeroAddress();
    error ZeroAmount();
    error Unauthorized(address caller);
    error CCTPDisabled();
}
