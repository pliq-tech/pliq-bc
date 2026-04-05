// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./libraries/PliqTypes.sol";
import "./libraries/PliqErrors.sol";

interface IWorldID {
    function verifyProof(uint256 root, uint256 groupId, uint256 signalHash, uint256 nullifierHash, uint256 externalNullifierHash, uint256[8] calldata proof) external;
}

/// @title PliqRegistry - User, listing, and application registry
/// @notice Manages World ID verified users, property listings, and rental applications
contract PliqRegistry is AccessControl, Pausable {
    IWorldID public worldIdRouter;
    uint256 public immutable groupId = 1;
    uint256 public immutable externalNullifier;

    mapping(uint256 => bool) private _usedNullifiers;
    mapping(address => PliqTypes.UserInfo) private _users;
    mapping(uint256 => PliqTypes.ListingInfo) private _listings;
    mapping(uint256 => PliqTypes.ApplicationInfo) private _applications;

    uint256 public listingCount;
    uint256 public applicationCount;

    event UserRegistered(address indexed user, uint256 nullifierHash, PliqTypes.VerificationLevel level);
    event ListingCreated(uint256 indexed listingId, address indexed owner);
    event ListingStatusUpdated(uint256 indexed listingId, PliqTypes.ListingStatus status);
    event ApplicationSubmitted(uint256 indexed applicationId, uint256 indexed listingId, address indexed applicant);
    event ApplicationStatusUpdated(uint256 indexed applicationId, PliqTypes.ApplicationStatus status);

    constructor(address _worldIdRouter, string memory _actionId) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        worldIdRouter = IWorldID(_worldIdRouter);
        externalNullifier = uint256(keccak256(abi.encodePacked(_actionId)));
    }

    /// @notice Register a new user with World ID proof
    function registerUser(uint256 root, uint256 nullifierHash, uint256[8] calldata proof, PliqTypes.VerificationLevel level) external whenNotPaused {
        if (_usedNullifiers[nullifierHash]) revert PliqErrors.AlreadyRegistered(nullifierHash);
        uint256 signalHash = uint256(keccak256(abi.encodePacked(msg.sender)));
        worldIdRouter.verifyProof(root, groupId, signalHash, nullifierHash, externalNullifier, proof);
        _usedNullifiers[nullifierHash] = true;
        _users[msg.sender] = PliqTypes.UserInfo({ userAddress: msg.sender, nullifierHash: nullifierHash, verificationLevel: level, registrationTimestamp: uint64(block.timestamp), isActive: true });
        emit UserRegistered(msg.sender, nullifierHash, level);
    }

    /// @notice Create a new property listing
    function createListing(bytes32 listingHash, uint128 deposit, uint128 monthlyRent, string calldata metadataURI) external whenNotPaused {
        if (_users[msg.sender].registrationTimestamp == 0) revert PliqErrors.NotRegistered(msg.sender);
        if (uint8(_users[msg.sender].verificationLevel) < uint8(PliqTypes.VerificationLevel.Device)) revert PliqErrors.InsufficientVerification(uint8(PliqTypes.VerificationLevel.Device), uint8(_users[msg.sender].verificationLevel));
        listingCount++;
        _listings[listingCount] = PliqTypes.ListingInfo({ owner: msg.sender, listingHash: listingHash, deposit: deposit, monthlyRent: monthlyRent, metadataURI: metadataURI, status: PliqTypes.ListingStatus.Active, createdAt: uint64(block.timestamp) });
        emit ListingCreated(listingCount, msg.sender);
    }

    /// @notice Apply for a rental listing
    function applyForRental(uint256 listingId) external whenNotPaused {
        if (_users[msg.sender].registrationTimestamp == 0) revert PliqErrors.NotRegistered(msg.sender);
        if (uint8(_users[msg.sender].verificationLevel) < uint8(PliqTypes.VerificationLevel.Orb)) revert PliqErrors.InsufficientVerification(uint8(PliqTypes.VerificationLevel.Orb), uint8(_users[msg.sender].verificationLevel));
        if (_listings[listingId].createdAt == 0) revert PliqErrors.ListingNotFound(listingId);
        if (_listings[listingId].status != PliqTypes.ListingStatus.Active) revert PliqErrors.ListingNotActive(listingId);
        applicationCount++;
        _applications[applicationCount] = PliqTypes.ApplicationInfo({ applicant: msg.sender, listingId: listingId, status: PliqTypes.ApplicationStatus.Pending, appliedAt: uint64(block.timestamp) });
        emit ApplicationSubmitted(applicationCount, listingId, msg.sender);
    }

    /// @notice Accept an application (listing owner only)
    function acceptApplication(uint256 applicationId) external whenNotPaused {
        PliqTypes.ApplicationInfo storage app = _applications[applicationId];
        if (app.appliedAt == 0) revert PliqErrors.ApplicationNotFound(applicationId);
        if (_listings[app.listingId].owner != msg.sender) revert PliqErrors.NotListingOwner(msg.sender, _listings[app.listingId].owner);
        app.status = PliqTypes.ApplicationStatus.Accepted;
        emit ApplicationStatusUpdated(applicationId, PliqTypes.ApplicationStatus.Accepted);
    }

    /// @notice Reject an application (listing owner only)
    function rejectApplication(uint256 applicationId) external whenNotPaused {
        PliqTypes.ApplicationInfo storage app = _applications[applicationId];
        if (app.appliedAt == 0) revert PliqErrors.ApplicationNotFound(applicationId);
        if (_listings[app.listingId].owner != msg.sender) revert PliqErrors.NotListingOwner(msg.sender, _listings[app.listingId].owner);
        app.status = PliqTypes.ApplicationStatus.Rejected;
        emit ApplicationStatusUpdated(applicationId, PliqTypes.ApplicationStatus.Rejected);
    }

    /// @notice Withdraw own application
    function withdrawApplication(uint256 applicationId) external whenNotPaused {
        PliqTypes.ApplicationInfo storage app = _applications[applicationId];
        if (app.applicant != msg.sender) revert PliqErrors.NotDisputeParty(msg.sender);
        app.status = PliqTypes.ApplicationStatus.Withdrawn;
        emit ApplicationStatusUpdated(applicationId, PliqTypes.ApplicationStatus.Withdrawn);
    }

    function getUserByAddress(address user) external view returns (PliqTypes.UserInfo memory) { return _users[user]; }
    function getListingById(uint256 id) external view returns (PliqTypes.ListingInfo memory) { return _listings[id]; }
    function getApplicationById(uint256 id) external view returns (PliqTypes.ApplicationInfo memory) { return _applications[id]; }
    function isRegistered(address user) external view returns (bool) { return _users[user].registrationTimestamp > 0; }
    function setWorldIDRouter(address router) external onlyRole(DEFAULT_ADMIN_ROLE) { worldIdRouter = IWorldID(router); }
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
