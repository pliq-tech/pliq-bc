// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/PliqRegistry.sol";
import "../src/RentalAgreement.sol";
import "../src/StakingManager.sol";
import "../src/ReputationAccumulator.sol";
import "../src/PaymentRouter.sol";
import "../src/DisputeResolver.sol";
import "./helpers/MockWorldID.sol";
import "./helpers/MockERC20.sol";
import "./helpers/Constants.sol";

/// @title Integration Tests - Full flow and cross-contract role verification
contract IntegrationTest is Test {
    MockWorldID worldId;
    MockERC20 usdc;
    PliqRegistry registry;
    RentalAgreement agreement;
    StakingManager staking;
    ReputationAccumulator reputation;
    PaymentRouter router;
    DisputeResolver dispute;

    address admin = address(this);
    address landlord = Constants.LANDLORD;
    address tenant = Constants.TENANT;
    address treasury = Constants.TREASURY;

    function setUp() public {
        // Deploy infrastructure
        worldId = new MockWorldID();
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Deploy contracts in dependency order
        registry = new PliqRegistry(address(worldId), Constants.ACTION_ID);
        staking = new StakingManager(address(registry), treasury);
        reputation = new ReputationAccumulator(address(registry));
        router = new PaymentRouter(treasury);
        agreement = new RentalAgreement(address(registry), address(router), address(staking));
        dispute = new DisputeResolver(address(agreement), address(staking), address(reputation));

        // Grant cross-contract roles
        bytes32 DISPUTE_RESOLVER_ROLE = keccak256("DISPUTE_RESOLVER_ROLE");
        staking.grantRole(DISPUTE_RESOLVER_ROLE, address(dispute));

        bytes32 KEEPER_ROLE = keccak256("KEEPER_ROLE");
        router.grantRole(KEEPER_ROLE, address(this));

        bytes32 ORACLE_ROLE = keccak256("ORACLE_ROLE");
        reputation.grantRole(ORACLE_ROLE, Constants.ORACLE);

        // Configure tokens
        router.addSupportedToken(address(usdc));

        // Mint tokens
        usdc.mint(landlord, 100_000e6);
        usdc.mint(tenant, 100_000e6);

        // Register users
        uint256[8] memory proof;
        vm.prank(landlord);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_1, proof);
        vm.prank(tenant);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_2, proof);
    }

    /// @notice Full lifecycle: register -> list -> apply -> accept -> agreement -> deposit -> rent -> move-in -> move-out -> release
    function test_FullRentalLifecycle() public {
        // 1. Landlord creates listing
        vm.prank(landlord);
        uint256 listingId = registry.createListing(
            Constants.LISTING_HASH,
            Constants.DEPOSIT_AMOUNT,
            Constants.MONTHLY_RENT,
            Constants.METADATA_URI
        );
        assertEq(listingId, 1);

        // 2. Tenant applies
        vm.prank(tenant);
        uint256 appId = registry.applyForRental(listingId);
        assertEq(appId, 1);

        // 3. Landlord accepts
        vm.prank(landlord);
        registry.acceptApplication(appId);

        // 4. Landlord creates agreement
        uint64 startDate = uint64(block.timestamp) + 30 days;
        uint64 endDate = startDate + 365 days;
        vm.prank(landlord);
        uint256 agreementId = agreement.createAgreement(
            listingId, appId, Constants.LEASE_HASH, startDate, endDate
        );
        assertEq(agreementId, 1);

        // Verify agreement data
        PliqTypes.Agreement memory a = agreement.getAgreementById(agreementId);
        assertEq(a.landlord, landlord);
        assertEq(a.tenant, tenant);
        assertEq(uint8(a.status), uint8(PliqTypes.AgreementStatus.Created));

        // 5. Tenant pays deposit
        vm.startPrank(tenant);
        usdc.approve(address(agreement), Constants.DEPOSIT_AMOUNT);
        agreement.payDeposit(agreementId, address(usdc));
        vm.stopPrank();

        assertEq(agreement.getEscrowBalance(agreementId), Constants.DEPOSIT_AMOUNT);
        a = agreement.getAgreementById(agreementId);
        assertEq(uint8(a.status), uint8(PliqTypes.AgreementStatus.DepositPaid));

        // 6. Both confirm move-in
        vm.prank(landlord);
        agreement.confirmMoveIn(agreementId, Constants.CONDITION_REPORT_HASH);

        vm.prank(tenant);
        agreement.confirmMoveIn(agreementId, bytes32(0));

        a = agreement.getAgreementById(agreementId);
        assertEq(uint8(a.status), uint8(PliqTypes.AgreementStatus.MoveInComplete));

        // 7. Tenant pays rent
        vm.startPrank(tenant);
        usdc.approve(address(agreement), Constants.MONTHLY_RENT);
        agreement.payRent(agreementId, address(usdc));
        vm.stopPrank();

        // 8. Initiate move-out
        vm.prank(tenant);
        agreement.initiateMoveOut(agreementId);

        a = agreement.getAgreementById(agreementId);
        assertEq(uint8(a.status), uint8(PliqTypes.AgreementStatus.MoveOutInitiated));

        // 9. Confirm move-out
        vm.prank(landlord);
        agreement.confirmMoveOut(agreementId, Constants.CHECKOUT_REPORT_HASH);

        a = agreement.getAgreementById(agreementId);
        assertEq(uint8(a.status), uint8(PliqTypes.AgreementStatus.MoveOutComplete));

        // 10. Release deposit (full)
        uint256 tenantBalBefore = usdc.balanceOf(tenant);
        vm.prank(landlord);
        agreement.releaseDeposit(agreementId, 0);

        assertEq(usdc.balanceOf(tenant), tenantBalBefore + Constants.DEPOSIT_AMOUNT);
        assertEq(agreement.getEscrowBalance(agreementId), 0);
    }

    /// @notice Dispute resolution triggers slash in StakingManager
    function test_DisputeResolutionSlash() public {
        // Setup: listing + application + agreement
        vm.prank(landlord);
        uint256 listingId = registry.createListing(
            Constants.LISTING_HASH, Constants.DEPOSIT_AMOUNT, Constants.MONTHLY_RENT, Constants.METADATA_URI
        );

        vm.prank(tenant);
        uint256 appId = registry.applyForRental(listingId);

        vm.prank(landlord);
        registry.acceptApplication(appId);

        vm.prank(landlord);
        uint256 agreementId = agreement.createAgreement(
            listingId, appId, Constants.LEASE_HASH,
            uint64(block.timestamp) + 30 days,
            uint64(block.timestamp) + 395 days
        );

        // Tenant pays deposit
        vm.startPrank(tenant);
        usdc.approve(address(agreement), Constants.DEPOSIT_AMOUNT);
        agreement.payDeposit(agreementId, address(usdc));
        vm.stopPrank();

        // Tenant stakes for rent
        vm.startPrank(tenant);
        usdc.approve(address(staking), Constants.STAKE_AMOUNT);
        uint256 stakeId = staking.stakeToRent(agreementId, Constants.STAKE_AMOUNT, address(usdc));
        vm.stopPrank();

        // Landlord raises dispute
        vm.prank(landlord);
        uint256 disputeId = dispute.raiseDispute(agreementId, "Lease violation", Constants.EVIDENCE_HASH);

        // Advance past evidence deadline
        vm.warp(block.timestamp + 8 days);

        // Operator selects jurors
        dispute.selectJurors(disputeId);

        // Jurors vote (get juror addresses)
        address[] memory jurors = dispute.getJurors(disputeId);
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            dispute.castVote(disputeId, true); // All vote for initiator (landlord)
        }

        // Resolve dispute
        dispute.resolveDispute(disputeId);

        PliqTypes.Dispute memory d = dispute.getDisputeById(disputeId);
        assertEq(uint8(d.status), uint8(PliqTypes.DisputeStatus.Resolved));
        assertGt(d.totalVotesFor, d.totalVotesAgainst);

        // Now slash the tenant's stake (operator action based on dispute outcome)
        uint128 slashAmount = 50e6;
        staking.slash(stakeId, slashAmount, "Dispute lost");

        PliqTypes.Stake memory s = staking.getStakeById(stakeId);
        assertEq(s.amount, Constants.STAKE_AMOUNT - slashAmount);
    }

    /// @notice Cross-contract roles: DISPUTE_RESOLVER_ROLE granted to DisputeResolver in StakingManager
    function test_CrossContractRoles() public {
        bytes32 DISPUTE_RESOLVER_ROLE = keccak256("DISPUTE_RESOLVER_ROLE");
        assertTrue(staking.hasRole(DISPUTE_RESOLVER_ROLE, address(dispute)));
    }

    /// @notice KEEPER_ROLE works for PaymentRouter recurring payments
    function test_KeeperRoleRecurringPayment() public {
        uint256 scheduleId = router.setupRecurringPayment(1, Constants.MONTHLY_RENT, address(usdc), 30);
        assertEq(scheduleId, 1);

        PliqTypes.RecurringSchedule memory s = router.getRecurringSchedule(1);
        assertTrue(s.active);
    }

    /// @notice ORACLE_ROLE works for ReputationAccumulator Merkle commits
    function test_OracleRoleMerkleCommit() public {
        bytes32 root = keccak256("merkle-root");
        uint64 ts = uint64(block.timestamp);

        vm.prank(Constants.ORACLE);
        reputation.commitMerkleRoot(root, ts);

        (bytes32 storedRoot, uint64 storedTs) = reputation.getLatestMerkleRoot();
        assertEq(storedRoot, root);
        assertEq(storedTs, ts);
    }

    /// @notice Pause blocks all write functions
    function test_PauseBlocksWrites() public {
        registry.pause();

        uint256[8] memory proof;
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        registry.registerUser(Constants.ROOT, 999, proof);

        registry.unpause();

        // Should work after unpause
        vm.prank(address(0xDEAD));
        registry.registerUser(Constants.ROOT, 999, proof);
    }
}
