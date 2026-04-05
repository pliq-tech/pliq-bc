// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/PliqTypes.sol";

interface IRentalAgreement {
    // Write
    function createAgreement(
        uint256 listingId,
        uint256 applicationId,
        bytes32 leaseHash,
        uint64 startDate,
        uint64 endDate
    ) external returns (uint256 agreementId);

    function payDeposit(uint256 agreementId, address token) external;
    function payRent(uint256 agreementId, address token) external;

    function confirmMoveIn(uint256 agreementId, bytes32 conditionReportHash) external;
    function initiateMoveOut(uint256 agreementId) external;
    function confirmMoveOut(uint256 agreementId, bytes32 conditionReportHash) external;
    function releaseDeposit(uint256 agreementId, uint128 deductionAmount) external;
    function disputeDeduction(uint256 agreementId) external;
    function terminateEarly(uint256 agreementId, string calldata reason) external;

    // Read
    function getAgreementById(uint256 agreementId) external view returns (PliqTypes.Agreement memory);
    function getEscrowBalance(uint256 agreementId) external view returns (uint128);
    function getAgreementsByLandlord(address landlord) external view returns (uint256[] memory);
    function getAgreementsByTenant(address tenant) external view returns (uint256[] memory);

    // Events
    event AgreementCreated(uint256 indexed agreementId, address indexed landlord, address indexed tenant, uint256 listingId);
    event DepositPaid(uint256 indexed agreementId, uint128 amount, address token);
    event RentPaid(uint256 indexed agreementId, uint128 amount, address token, uint64 timestamp);
    event MoveInConfirmed(uint256 indexed agreementId, address indexed confirmer, bytes32 conditionReportHash);
    event MoveOutInitiated(uint256 indexed agreementId, address indexed initiator);
    event MoveOutConfirmed(uint256 indexed agreementId, address indexed confirmer, bytes32 conditionReportHash);
    event DepositReleased(uint256 indexed agreementId, uint128 toTenant, uint128 toLandlord);
    event AgreementTerminated(uint256 indexed agreementId, string reason);
    event DepositDisputed(uint256 indexed agreementId, address indexed disputer);
}
