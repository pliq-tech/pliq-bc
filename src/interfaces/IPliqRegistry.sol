// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/PliqTypes.sol";

interface IPliqRegistry {
    // Write
    function registerUser(
        uint256 root,
        uint256 nullifierHash,
        uint256[8] calldata proof
    ) external;

    function updateVerificationLevel(
        uint256 root,
        uint256 nullifierHash,
        uint256[8] calldata proof,
        PliqTypes.VerificationLevel newLevel
    ) external;

    function createListing(
        bytes32 listingHash,
        uint128 deposit,
        uint128 monthlyRent,
        string calldata metadataURI
    ) external returns (uint256 listingId);

    function updateListingStatus(uint256 listingId, PliqTypes.ListingStatus newStatus) external;

    function applyForRental(uint256 listingId) external returns (uint256 applicationId);
    function acceptApplication(uint256 applicationId) external;
    function rejectApplication(uint256 applicationId) external;
    function withdrawApplication(uint256 applicationId) external;

    // Read
    function getUserByAddress(address user) external view returns (PliqTypes.User memory);
    function getListingById(uint256 listingId) external view returns (PliqTypes.Listing memory);
    function getApplicationById(uint256 applicationId) external view returns (PliqTypes.Application memory);
    function isRegistered(address user) external view returns (bool);
    function getListingCount() external view returns (uint256);

    // Events
    event UserRegistered(address indexed user, uint256 nullifierHash, PliqTypes.VerificationLevel level);
    event VerificationLevelUpdated(address indexed user, PliqTypes.VerificationLevel oldLevel, PliqTypes.VerificationLevel newLevel);
    event ListingCreated(uint256 indexed listingId, address indexed owner, bytes32 listingHash);
    event ListingStatusChanged(uint256 indexed listingId, PliqTypes.ListingStatus oldStatus, PliqTypes.ListingStatus newStatus);
    event ApplicationCreated(uint256 indexed applicationId, address indexed applicant, uint256 indexed listingId);
    event ApplicationStatusChanged(uint256 indexed applicationId, PliqTypes.ApplicationStatus oldStatus, PliqTypes.ApplicationStatus newStatus);
}
