// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/PliqRegistry.sol";
import "../src/libraries/PliqTypes.sol";
import "../src/libraries/PliqErrors.sol";
import "./helpers/MockWorldID.sol";
import "./helpers/Constants.sol";

contract PliqRegistryTest is Test {
    PliqRegistry internal registry;
    MockWorldID internal mockWorldID;

    address internal admin = address(this);
    address internal landlord = Constants.LANDLORD;
    address internal tenant = Constants.TENANT;
    address internal randomUser = Constants.RANDOM_USER;

    uint256[8] internal dummyProof;

    event UserRegistered(address indexed user, uint256 nullifierHash, PliqTypes.VerificationLevel level);
    event ListingCreated(uint256 indexed listingId, address indexed owner, bytes32 listingHash);
    event ApplicationCreated(uint256 indexed applicationId, address indexed applicant, uint256 indexed listingId);
    event ApplicationStatusChanged(uint256 indexed applicationId, PliqTypes.ApplicationStatus oldStatus, PliqTypes.ApplicationStatus newStatus);
    event VerificationLevelUpdated(address indexed user, PliqTypes.VerificationLevel oldLevel, PliqTypes.VerificationLevel newLevel);

    function setUp() public {
        mockWorldID = new MockWorldID();
        registry = new PliqRegistry(address(mockWorldID), Constants.ACTION_ID);
    }

    // --- Registration ---

    function test_RegisterUser_Success() public {
        vm.expectEmit(true, false, false, true);
        emit UserRegistered(landlord, Constants.NULLIFIER_1, PliqTypes.VerificationLevel.Orb);

        vm.prank(landlord);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_1, dummyProof);

        PliqTypes.User memory user = registry.getUserByAddress(landlord);
        assertEq(user.userAddress, landlord);
        assertEq(user.nullifierHash, Constants.NULLIFIER_1);
        assertEq(uint8(user.verificationLevel), uint8(PliqTypes.VerificationLevel.Orb));
        assertTrue(user.isActive);
        assertTrue(registry.isRegistered(landlord));
    }

    function test_RegisterUser_DuplicateNullifier_Reverts() public {
        vm.prank(landlord);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_1, dummyProof);

        vm.prank(tenant);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.AlreadyRegistered.selector, Constants.NULLIFIER_1));
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_1, dummyProof);
    }

    function test_RegisterUser_InvalidProof_Reverts() public {
        mockWorldID.setShouldRevert(true);
        vm.prank(landlord);
        vm.expectRevert();
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_1, dummyProof);
    }

    // --- Verification Level ---

    function test_UpdateVerificationLevel_UpgradeToPassport() public {
        vm.prank(landlord);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_1, dummyProof);

        vm.expectEmit(true, false, false, true);
        emit VerificationLevelUpdated(landlord, PliqTypes.VerificationLevel.Orb, PliqTypes.VerificationLevel.Passport);

        vm.prank(landlord);
        registry.updateVerificationLevel(Constants.ROOT, Constants.NULLIFIER_2, dummyProof, PliqTypes.VerificationLevel.Passport);

        PliqTypes.User memory user = registry.getUserByAddress(landlord);
        assertEq(uint8(user.verificationLevel), uint8(PliqTypes.VerificationLevel.Passport));
    }

    function test_UpdateVerificationLevel_Downgrade_Reverts() public {
        vm.prank(landlord);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_1, dummyProof);

        vm.prank(landlord);
        vm.expectRevert(abi.encodeWithSelector(
            PliqErrors.InsufficientVerification.selector,
            uint8(PliqTypes.VerificationLevel.Device),
            uint8(PliqTypes.VerificationLevel.Orb)
        ));
        registry.updateVerificationLevel(Constants.ROOT, Constants.NULLIFIER_2, dummyProof, PliqTypes.VerificationLevel.Device);
    }

    function test_UpdateVerificationLevel_Unregistered_Reverts() public {
        vm.prank(landlord);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.NotRegistered.selector, landlord));
        registry.updateVerificationLevel(Constants.ROOT, Constants.NULLIFIER_1, dummyProof, PliqTypes.VerificationLevel.Passport);
    }

    // --- Listings ---

    function test_CreateListing_Success() public {
        vm.prank(landlord);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_1, dummyProof);

        vm.expectEmit(true, true, false, true);
        emit ListingCreated(1, landlord, Constants.LISTING_HASH);

        vm.prank(landlord);
        uint256 listingId = registry.createListing(Constants.LISTING_HASH, Constants.DEPOSIT_AMOUNT, Constants.MONTHLY_RENT, Constants.METADATA_URI);

        assertEq(listingId, 1);
        assertEq(registry.getListingCount(), 1);

        PliqTypes.Listing memory listing = registry.getListingById(listingId);
        assertEq(listing.owner, landlord);
        assertEq(listing.deposit, Constants.DEPOSIT_AMOUNT);
        assertEq(listing.monthlyRent, Constants.MONTHLY_RENT);
        assertEq(uint8(listing.status), uint8(PliqTypes.ListingStatus.Active));
    }

    function test_CreateListing_Unregistered_Reverts() public {
        vm.prank(landlord);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.NotRegistered.selector, landlord));
        registry.createListing(Constants.LISTING_HASH, Constants.DEPOSIT_AMOUNT, Constants.MONTHLY_RENT, Constants.METADATA_URI);
    }

    // --- Applications ---

    function test_ApplyForRental_OrbVerified_Success() public {
        _registerAndCreateListing();

        vm.prank(tenant);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_2, dummyProof);

        vm.expectEmit(true, true, true, true);
        emit ApplicationCreated(1, tenant, 1);

        vm.prank(tenant);
        uint256 appId = registry.applyForRental(1);
        assertEq(appId, 1);

        PliqTypes.Application memory app = registry.getApplicationById(appId);
        assertEq(app.applicant, tenant);
        assertEq(app.listingId, 1);
        assertEq(uint8(app.status), uint8(PliqTypes.ApplicationStatus.Pending));
    }

    function test_ApplyForRental_Unregistered_Reverts() public {
        _registerAndCreateListing();

        vm.prank(randomUser);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.NotRegistered.selector, randomUser));
        registry.applyForRental(1);
    }

    function test_ApplyForRental_ListingNotFound_Reverts() public {
        vm.prank(tenant);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_2, dummyProof);

        vm.prank(tenant);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.ListingNotFound.selector, 999));
        registry.applyForRental(999);
    }

    // --- Accept/Reject/Withdraw ---

    function test_AcceptApplication_ByOwner() public {
        (uint256 appId,) = _createApplication();

        vm.prank(landlord);
        registry.acceptApplication(appId);

        PliqTypes.Application memory app = registry.getApplicationById(appId);
        assertEq(uint8(app.status), uint8(PliqTypes.ApplicationStatus.Accepted));
    }

    function test_AcceptApplication_ByNonOwner_Reverts() public {
        (uint256 appId,) = _createApplication();

        vm.prank(tenant);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.NotListingOwner.selector, tenant, landlord));
        registry.acceptApplication(appId);
    }

    function test_RejectApplication_ByOwner() public {
        (uint256 appId,) = _createApplication();

        vm.prank(landlord);
        registry.rejectApplication(appId);

        PliqTypes.Application memory app = registry.getApplicationById(appId);
        assertEq(uint8(app.status), uint8(PliqTypes.ApplicationStatus.Rejected));
    }

    function test_WithdrawApplication_ByApplicant() public {
        (uint256 appId,) = _createApplication();

        vm.prank(tenant);
        registry.withdrawApplication(appId);

        PliqTypes.Application memory app = registry.getApplicationById(appId);
        assertEq(uint8(app.status), uint8(PliqTypes.ApplicationStatus.Withdrawn));
    }

    function test_WithdrawApplication_ByNonApplicant_Reverts() public {
        (uint256 appId,) = _createApplication();

        vm.prank(landlord);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.NotApplicant.selector, landlord, tenant));
        registry.withdrawApplication(appId);
    }

    // --- Pause ---

    function test_Pause_BlocksFunctions() public {
        registry.pause();

        vm.prank(landlord);
        vm.expectRevert();
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_1, dummyProof);
    }

    function test_Unpause_RestoresFunctions() public {
        registry.pause();
        registry.unpause();

        vm.prank(landlord);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_1, dummyProof);
        assertTrue(registry.isRegistered(landlord));
    }

    function test_Pause_ByNonAdmin_Reverts() public {
        vm.prank(landlord);
        vm.expectRevert();
        registry.pause();
    }

    // --- Helpers ---

    function _registerAndCreateListing() internal returns (uint256) {
        vm.prank(landlord);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_1, dummyProof);

        vm.prank(landlord);
        return registry.createListing(Constants.LISTING_HASH, Constants.DEPOSIT_AMOUNT, Constants.MONTHLY_RENT, Constants.METADATA_URI);
    }

    function _createApplication() internal returns (uint256 appId, uint256 listingId) {
        listingId = _registerAndCreateListing();

        vm.prank(tenant);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_2, dummyProof);

        vm.prank(tenant);
        appId = registry.applyForRental(listingId);
    }
}
