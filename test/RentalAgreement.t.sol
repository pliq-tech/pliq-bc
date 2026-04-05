// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/PliqRegistry.sol";
import "../src/RentalAgreement.sol";
import "../src/libraries/PliqTypes.sol";
import "../src/libraries/PliqErrors.sol";
import "./helpers/MockWorldID.sol";
import "./helpers/MockERC20.sol";
import "./helpers/Constants.sol";

contract RentalAgreementTest is Test {
    PliqRegistry internal registry;
    RentalAgreement internal agreement;
    MockWorldID internal mockWorldID;
    MockERC20 internal usdc;

    address internal admin = address(this);
    address internal landlord = Constants.LANDLORD;
    address internal tenant = Constants.TENANT;
    address internal randomUser = Constants.RANDOM_USER;

    uint256[8] internal dummyProof;
    uint256 internal listingId;
    uint256 internal appId;
    uint256 internal agreementId;

    event AgreementCreated(uint256 indexed agreementId, address indexed landlord, address indexed tenant, uint256 listingId);
    event DepositPaid(uint256 indexed agreementId, uint128 amount, address token);
    event MoveInConfirmed(uint256 indexed agreementId, address indexed confirmer, bytes32 conditionReportHash);
    event DepositReleased(uint256 indexed agreementId, uint128 toTenant, uint128 toLandlord);
    event DepositDisputed(uint256 indexed agreementId, address indexed disputer);

    function setUp() public {
        mockWorldID = new MockWorldID();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        registry = new PliqRegistry(address(mockWorldID), Constants.ACTION_ID);
        agreement = new RentalAgreement(address(registry), address(0), address(0));

        // Register users
        vm.prank(landlord);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_1, dummyProof);
        vm.prank(tenant);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_2, dummyProof);

        // Create listing + application
        vm.prank(landlord);
        listingId = registry.createListing(Constants.LISTING_HASH, Constants.DEPOSIT_AMOUNT, Constants.MONTHLY_RENT, Constants.METADATA_URI);
        vm.prank(tenant);
        appId = registry.applyForRental(listingId);
        vm.prank(landlord);
        registry.acceptApplication(appId);

        // Mint tokens
        usdc.mint(tenant, 100_000e6);
        usdc.mint(landlord, 100_000e6);
    }

    function _createAgreement() internal returns (uint256) {
        vm.prank(landlord);
        return agreement.createAgreement(listingId, appId, Constants.LEASE_HASH, uint64(block.timestamp) + 30 days, uint64(block.timestamp) + 395 days);
    }

    function _createAndPayDeposit() internal returns (uint256 id) {
        id = _createAgreement();
        vm.startPrank(tenant);
        usdc.approve(address(agreement), Constants.DEPOSIT_AMOUNT);
        agreement.payDeposit(id, address(usdc));
        vm.stopPrank();
    }

    // --- Create Agreement ---

    function test_CreateAgreement_Success() public {
        vm.prank(landlord);
        agreementId = agreement.createAgreement(listingId, appId, Constants.LEASE_HASH, uint64(block.timestamp) + 30 days, uint64(block.timestamp) + 395 days);

        assertEq(agreementId, 1);
        PliqTypes.Agreement memory a = agreement.getAgreementById(agreementId);
        assertEq(a.landlord, landlord);
        assertEq(a.tenant, tenant);
        assertEq(uint8(a.status), uint8(PliqTypes.AgreementStatus.Created));
    }

    function test_CreateAgreement_NotOwner_Reverts() public {
        vm.prank(tenant);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.NotListingOwner.selector, tenant, landlord));
        agreement.createAgreement(listingId, appId, Constants.LEASE_HASH, uint64(block.timestamp) + 30 days, uint64(block.timestamp) + 395 days);
    }

    // --- Pay Deposit ---

    function test_PayDeposit_Success() public {
        agreementId = _createAgreement();

        vm.startPrank(tenant);
        usdc.approve(address(agreement), Constants.DEPOSIT_AMOUNT);
        agreement.payDeposit(agreementId, address(usdc));
        vm.stopPrank();

        assertEq(agreement.getEscrowBalance(agreementId), Constants.DEPOSIT_AMOUNT);
        PliqTypes.Agreement memory a = agreement.getAgreementById(agreementId);
        assertEq(uint8(a.status), uint8(PliqTypes.AgreementStatus.DepositPaid));
    }

    function test_PayDeposit_Twice_Reverts() public {
        agreementId = _createAndPayDeposit();

        vm.startPrank(tenant);
        usdc.approve(address(agreement), Constants.DEPOSIT_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(
            PliqErrors.InvalidAgreementStatus.selector,
            uint8(PliqTypes.AgreementStatus.DepositPaid),
            uint8(PliqTypes.AgreementStatus.Created)
        ));
        agreement.payDeposit(agreementId, address(usdc));
        vm.stopPrank();
    }

    function test_PayDeposit_NotTenant_Reverts() public {
        agreementId = _createAgreement();

        vm.startPrank(landlord);
        usdc.approve(address(agreement), Constants.DEPOSIT_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.NotTenant.selector, landlord, tenant));
        agreement.payDeposit(agreementId, address(usdc));
        vm.stopPrank();
    }

    // --- Move In ---

    function test_ConfirmMoveIn_BothParties() public {
        agreementId = _createAndPayDeposit();

        vm.prank(landlord);
        agreement.confirmMoveIn(agreementId, Constants.CONDITION_REPORT_HASH);

        PliqTypes.Agreement memory a = agreement.getAgreementById(agreementId);
        assertEq(uint8(a.status), uint8(PliqTypes.AgreementStatus.Active));

        vm.prank(tenant);
        agreement.confirmMoveIn(agreementId, bytes32(0));

        a = agreement.getAgreementById(agreementId);
        assertEq(uint8(a.status), uint8(PliqTypes.AgreementStatus.MoveInComplete));
        assertTrue(a.landlordConfirmedMoveIn);
        assertTrue(a.tenantConfirmedMoveIn);
    }

    function test_ConfirmMoveIn_NonParty_Reverts() public {
        agreementId = _createAndPayDeposit();

        vm.prank(randomUser);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.NotAgreementParty.selector, randomUser));
        agreement.confirmMoveIn(agreementId, bytes32(0));
    }

    // --- Pay Rent ---

    function test_PayRent_Success() public {
        agreementId = _createAndPayDeposit();
        vm.prank(landlord);
        agreement.confirmMoveIn(agreementId, Constants.CONDITION_REPORT_HASH);
        vm.prank(tenant);
        agreement.confirmMoveIn(agreementId, bytes32(0));

        uint256 landlordBalBefore = usdc.balanceOf(landlord);
        vm.startPrank(tenant);
        usdc.approve(address(agreement), Constants.MONTHLY_RENT);
        agreement.payRent(agreementId, address(usdc));
        vm.stopPrank();

        assertEq(usdc.balanceOf(landlord), landlordBalBefore + Constants.MONTHLY_RENT);
    }

    // --- Move Out ---

    function test_InitiateMoveOut() public {
        agreementId = _createAndPayDeposit();
        vm.prank(landlord);
        agreement.confirmMoveIn(agreementId, Constants.CONDITION_REPORT_HASH);
        vm.prank(tenant);
        agreement.confirmMoveIn(agreementId, bytes32(0));

        vm.prank(tenant);
        agreement.initiateMoveOut(agreementId);

        PliqTypes.Agreement memory a = agreement.getAgreementById(agreementId);
        assertEq(uint8(a.status), uint8(PliqTypes.AgreementStatus.MoveOutInitiated));
    }

    function test_ConfirmMoveOut() public {
        agreementId = _createAndPayDeposit();
        vm.prank(landlord);
        agreement.confirmMoveIn(agreementId, Constants.CONDITION_REPORT_HASH);
        vm.prank(tenant);
        agreement.confirmMoveIn(agreementId, bytes32(0));
        vm.prank(tenant);
        agreement.initiateMoveOut(agreementId);

        vm.prank(landlord);
        agreement.confirmMoveOut(agreementId, Constants.CHECKOUT_REPORT_HASH);

        PliqTypes.Agreement memory a = agreement.getAgreementById(agreementId);
        assertEq(uint8(a.status), uint8(PliqTypes.AgreementStatus.MoveOutComplete));
    }

    // --- Release Deposit ---

    function test_ReleaseDeposit_Full() public {
        agreementId = _moveToMoveOutComplete();
        uint256 tenantBal = usdc.balanceOf(tenant);

        vm.prank(landlord);
        agreement.releaseDeposit(agreementId, 0);

        assertEq(usdc.balanceOf(tenant), tenantBal + Constants.DEPOSIT_AMOUNT);
        assertEq(agreement.getEscrowBalance(agreementId), 0);
    }

    function test_ReleaseDeposit_WithDeduction() public {
        agreementId = _moveToMoveOutComplete();
        uint128 deduction = 500e6;
        uint256 tenantBal = usdc.balanceOf(tenant);
        uint256 landlordBal = usdc.balanceOf(landlord);

        vm.prank(landlord);
        agreement.releaseDeposit(agreementId, deduction);

        assertEq(usdc.balanceOf(tenant), tenantBal + Constants.DEPOSIT_AMOUNT - deduction);
        assertEq(usdc.balanceOf(landlord), landlordBal + deduction);
    }

    function test_ReleaseDeposit_ExceedsDeposit_Reverts() public {
        agreementId = _moveToMoveOutComplete();

        vm.prank(landlord);
        vm.expectRevert(abi.encodeWithSelector(
            PliqErrors.DeductionExceedsDeposit.selector,
            Constants.DEPOSIT_AMOUNT + 1,
            Constants.DEPOSIT_AMOUNT
        ));
        agreement.releaseDeposit(agreementId, Constants.DEPOSIT_AMOUNT + 1);
    }

    // --- Dispute Deduction ---

    function test_DisputeDeduction_ByTenant() public {
        agreementId = _moveToMoveOutComplete();

        vm.prank(tenant);
        agreement.disputeDeduction(agreementId);

        PliqTypes.Agreement memory a = agreement.getAgreementById(agreementId);
        assertEq(uint8(a.status), uint8(PliqTypes.AgreementStatus.Disputed));
    }

    // --- Early Termination ---

    function test_TerminateEarly() public {
        agreementId = _createAndPayDeposit();

        vm.prank(tenant);
        agreement.terminateEarly(agreementId, "Moving away");

        PliqTypes.Agreement memory a = agreement.getAgreementById(agreementId);
        assertEq(uint8(a.status), uint8(PliqTypes.AgreementStatus.Terminated));
    }

    function test_TerminateEarly_NonParty_Reverts() public {
        agreementId = _createAndPayDeposit();

        vm.prank(randomUser);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.NotAgreementParty.selector, randomUser));
        agreement.terminateEarly(agreementId, "Unauthorized");
    }

    // --- View ---

    function test_GetAgreementsByLandlord() public {
        _createAgreement();
        uint256[] memory ids = agreement.getAgreementsByLandlord(landlord);
        assertEq(ids.length, 1);
        assertEq(ids[0], 1);
    }

    function test_GetAgreementsByTenant() public {
        _createAgreement();
        uint256[] memory ids = agreement.getAgreementsByTenant(tenant);
        assertEq(ids.length, 1);
        assertEq(ids[0], 1);
    }

    // --- Helpers ---

    function _moveToMoveOutComplete() internal returns (uint256 id) {
        id = _createAndPayDeposit();
        vm.prank(landlord);
        agreement.confirmMoveIn(id, Constants.CONDITION_REPORT_HASH);
        vm.prank(tenant);
        agreement.confirmMoveIn(id, bytes32(0));
        vm.prank(tenant);
        agreement.initiateMoveOut(id);
        vm.prank(landlord);
        agreement.confirmMoveOut(id, Constants.CHECKOUT_REPORT_HASH);
    }
}
