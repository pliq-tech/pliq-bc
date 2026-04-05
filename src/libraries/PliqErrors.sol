// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library PliqErrors {
    error AlreadyRegistered(uint256 nullifierHash);
    error NotRegistered(address user);
    error InsufficientVerification(uint8 required, uint8 actual);
    error InvalidWorldIDProof();
    error ListingNotFound(uint256 listingId);
    error ApplicationNotFound(uint256 applicationId);
    error NotListingOwner(address caller, address owner);
    error ListingNotActive(uint256 listingId);
    error AlreadyApplied(address applicant, uint256 listingId);
    error InvalidApplicationStatus(uint8 current, uint8 expected);
    error AgreementNotFound(uint256 agreementId);
    error InvalidAgreementStatus(uint8 current, uint8 expected);
    error NotAgreementParty(address caller);
    error DepositAlreadyPaid();
    error DeductionExceedsDeposit(uint128 deduction, uint128 deposit);
    error NotLandlord(address caller, address landlord);
    error NotTenant(address caller, address tenant);
    error InsufficientStakeAmount(uint128 amount, uint128 minimum);
    error StakeAlreadyReleased(uint256 stakeId);
    error SlashExceedsStake(uint128 slashAmount, uint128 stakeAmount);
    error StakeNotActive(uint256 stakeId);
    error SBTAlreadyMinted(address user);
    error SoulboundTransferBlocked();
    error TokenNotSupported(address token);
    error FeeTooHigh(uint16 fee, uint16 max);
    error EvidenceDeadlinePassed(uint64 deadline);
    error NotSelectedJuror(address caller);
    error AlreadyVoted(address juror);
    error AppealWindowExpired();
    error InsufficientAppealStake();
    error NotDisputeParty(address caller);
    error ZeroAddress();
    error ZeroAmount();
}
