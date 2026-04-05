// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./libraries/PliqTypes.sol";
import "./libraries/PliqErrors.sol";
import "./interfaces/IPliqRegistry.sol";

interface IWorldID {
    function verifyProof(
        uint256 root,
        uint256 groupId,
        uint256 signalHash,
        uint256 nullifierHash,
        uint256 externalNullifierHash,
        uint256[8] calldata proof
    ) external;
}

/// @title PliqRegistry - User, listing, and application registry with World ID verification
/// @notice Manages World ID verified users, property listings, and rental applications
contract PliqRegistry is AccessControl, Pausable, IPliqRegistry {
    IWorldID public worldIdRouter;
    uint256 public immutable groupId = 1;
    uint256 public immutable externalNullifier;

    mapping(uint256 => bool) private _usedNullifiers;
    mapping(address => PliqTypes.User) private _users;
    mapping(uint256 => PliqTypes.Listing) private _listings;
    mapping(uint256 => PliqTypes.Application) private _applications;

    uint256 private _listingCount;
    uint256 private _applicationCount;

    constructor(address _worldIdRouter, string memory _actionId) {
        if (_worldIdRouter == address(0)) revert PliqErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        worldIdRouter = IWorldID(_worldIdRouter);
        externalNullifier = uint256(keccak256(abi.encodePacked(_actionId)));
    }

    /// @notice Register a new user with World ID proof
    function registerUser(
        uint256 root,
        uint256 nullifierHash,
        uint256[8] calldata proof
    ) external whenNotPaused {
        if (_usedNullifiers[nullifierHash]) revert PliqErrors.AlreadyRegistered(nullifierHash);

        uint256 signalHash = uint256(keccak256(abi.encodePacked(msg.sender)));
        worldIdRouter.verifyProof(root, groupId, signalHash, nullifierHash, externalNullifier, proof);

        _usedNullifiers[nullifierHash] = true;
        _users[msg.sender] = PliqTypes.User({
            userAddress: msg.sender,
            nullifierHash: nullifierHash,
            verificationLevel: PliqTypes.VerificationLevel.Orb,
            registrationTimestamp: uint64(block.timestamp),
            isActive: true
        });

        emit UserRegistered(msg.sender, nullifierHash, PliqTypes.VerificationLevel.Orb);
    }

    /// @notice Update verification level with a new World ID proof
    function updateVerificationLevel(
        uint256 root,
        uint256 nullifierHash,
        uint256[8] calldata proof,
        PliqTypes.VerificationLevel newLevel
    ) external whenNotPaused {
        PliqTypes.User storage user = _users[msg.sender];
        if (user.registrationTimestamp == 0) revert PliqErrors.NotRegistered(msg.sender);

        // Only allow upgrades
        if (uint8(newLevel) <= uint8(user.verificationLevel)) {
            revert PliqErrors.InsufficientVerification(uint8(newLevel), uint8(user.verificationLevel));
        }

        uint256 signalHash = uint256(keccak256(abi.encodePacked(msg.sender)));
        worldIdRouter.verifyProof(root, groupId, signalHash, nullifierHash, externalNullifier, proof);

        PliqTypes.VerificationLevel oldLevel = user.verificationLevel;
        user.verificationLevel = newLevel;

        emit VerificationLevelUpdated(msg.sender, oldLevel, newLevel);
    }

    /// @notice Create a new property listing (requires Device+ verification)
    function createListing(
        bytes32 listingHash,
        uint128 deposit,
        uint128 monthlyRent,
        string calldata metadataURI
    ) external whenNotPaused returns (uint256) {
        PliqTypes.User storage user = _users[msg.sender];
        if (user.registrationTimestamp == 0) revert PliqErrors.NotRegistered(msg.sender);
        if (uint8(user.verificationLevel) < uint8(PliqTypes.VerificationLevel.Device)) {
            revert PliqErrors.InsufficientVerification(
                uint8(PliqTypes.VerificationLevel.Device),
                uint8(user.verificationLevel)
            );
        }

        _listingCount++;
        _listings[_listingCount] = PliqTypes.Listing({
            owner: msg.sender,
            listingHash: listingHash,
            deposit: deposit,
            monthlyRent: monthlyRent,
            metadataURI: metadataURI,
            status: PliqTypes.ListingStatus.Active,
            createdAt: uint64(block.timestamp)
        });

        emit ListingCreated(_listingCount, msg.sender, listingHash);
        return _listingCount;
    }

    /// @notice Update listing status (owner only, validates state transitions)
    function updateListingStatus(uint256 listingId, PliqTypes.ListingStatus newStatus) external whenNotPaused {
        PliqTypes.Listing storage listing = _listings[listingId];
        if (listing.createdAt == 0) revert PliqErrors.ListingNotFound(listingId);
        if (listing.owner != msg.sender) revert PliqErrors.NotListingOwner(msg.sender, listing.owner);

        PliqTypes.ListingStatus oldStatus = listing.status;
        listing.status = newStatus;

        emit ListingStatusChanged(listingId, oldStatus, newStatus);
    }

    /// @notice Apply for a rental listing (requires Orb+ verification)
    function applyForRental(uint256 listingId) external whenNotPaused returns (uint256) {
        PliqTypes.User storage user = _users[msg.sender];
        if (user.registrationTimestamp == 0) revert PliqErrors.NotRegistered(msg.sender);
        if (uint8(user.verificationLevel) < uint8(PliqTypes.VerificationLevel.Orb)) {
            revert PliqErrors.InsufficientVerification(
                uint8(PliqTypes.VerificationLevel.Orb),
                uint8(user.verificationLevel)
            );
        }

        PliqTypes.Listing storage listing = _listings[listingId];
        if (listing.createdAt == 0) revert PliqErrors.ListingNotFound(listingId);
        if (listing.status != PliqTypes.ListingStatus.Active) revert PliqErrors.ListingNotActive(listingId);

        _applicationCount++;
        _applications[_applicationCount] = PliqTypes.Application({
            applicant: msg.sender,
            listingId: listingId,
            status: PliqTypes.ApplicationStatus.Pending,
            appliedAt: uint64(block.timestamp)
        });

        emit ApplicationCreated(_applicationCount, msg.sender, listingId);
        return _applicationCount;
    }

    /// @notice Accept an application (listing owner only)
    function acceptApplication(uint256 applicationId) external whenNotPaused {
        PliqTypes.Application storage app = _applications[applicationId];
        if (app.appliedAt == 0) revert PliqErrors.ApplicationNotFound(applicationId);
        if (app.status != PliqTypes.ApplicationStatus.Pending) {
            revert PliqErrors.InvalidApplicationStatus(uint8(app.status), uint8(PliqTypes.ApplicationStatus.Pending));
        }
        if (_listings[app.listingId].owner != msg.sender) {
            revert PliqErrors.NotListingOwner(msg.sender, _listings[app.listingId].owner);
        }

        PliqTypes.ApplicationStatus oldStatus = app.status;
        app.status = PliqTypes.ApplicationStatus.Accepted;
        emit ApplicationStatusChanged(applicationId, oldStatus, PliqTypes.ApplicationStatus.Accepted);
    }

    /// @notice Reject an application (listing owner only)
    function rejectApplication(uint256 applicationId) external whenNotPaused {
        PliqTypes.Application storage app = _applications[applicationId];
        if (app.appliedAt == 0) revert PliqErrors.ApplicationNotFound(applicationId);
        if (app.status != PliqTypes.ApplicationStatus.Pending) {
            revert PliqErrors.InvalidApplicationStatus(uint8(app.status), uint8(PliqTypes.ApplicationStatus.Pending));
        }
        if (_listings[app.listingId].owner != msg.sender) {
            revert PliqErrors.NotListingOwner(msg.sender, _listings[app.listingId].owner);
        }

        PliqTypes.ApplicationStatus oldStatus = app.status;
        app.status = PliqTypes.ApplicationStatus.Rejected;
        emit ApplicationStatusChanged(applicationId, oldStatus, PliqTypes.ApplicationStatus.Rejected);
    }

    /// @notice Withdraw own application (applicant only)
    function withdrawApplication(uint256 applicationId) external whenNotPaused {
        PliqTypes.Application storage app = _applications[applicationId];
        if (app.appliedAt == 0) revert PliqErrors.ApplicationNotFound(applicationId);
        if (app.applicant != msg.sender) revert PliqErrors.NotApplicant(msg.sender, app.applicant);
        if (app.status != PliqTypes.ApplicationStatus.Pending) {
            revert PliqErrors.InvalidApplicationStatus(uint8(app.status), uint8(PliqTypes.ApplicationStatus.Pending));
        }

        PliqTypes.ApplicationStatus oldStatus = app.status;
        app.status = PliqTypes.ApplicationStatus.Withdrawn;
        emit ApplicationStatusChanged(applicationId, oldStatus, PliqTypes.ApplicationStatus.Withdrawn);
    }

    // View functions
    function getUserByAddress(address user) external view returns (PliqTypes.User memory) { return _users[user]; }
    function getListingById(uint256 id) external view returns (PliqTypes.Listing memory) { return _listings[id]; }
    function getApplicationById(uint256 id) external view returns (PliqTypes.Application memory) { return _applications[id]; }
    function isRegistered(address user) external view returns (bool) { return _users[user].registrationTimestamp > 0; }
    function getListingCount() external view returns (uint256) { return _listingCount; }

    // Admin functions
    function setWorldIDRouter(address router) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (router == address(0)) revert PliqErrors.ZeroAddress();
        worldIdRouter = IWorldID(router);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
