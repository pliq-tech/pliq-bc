// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/DisputeResolver.sol";
import "../src/RentalAgreement.sol";
import "../src/StakingManager.sol";
import "../src/ReputationAccumulator.sol";
import "../src/PliqRegistry.sol";
import "../src/libraries/PliqTypes.sol";
import "../src/libraries/PliqErrors.sol";
import "./helpers/MockWorldID.sol";
import "./helpers/MockERC20.sol";
import "./helpers/Constants.sol";

contract DisputeResolverTest is Test {
    DisputeResolver internal dispute;
    RentalAgreement internal agreement;
    StakingManager internal staking;
    ReputationAccumulator internal reputation;
    PliqRegistry internal registry;
    MockWorldID internal mockWorldID;
    MockERC20 internal usdc;

    address internal admin = address(this);
    address internal landlord = Constants.LANDLORD;
    address internal tenant = Constants.TENANT;
    address internal treasury = Constants.TREASURY;

    uint256[8] internal dummyProof;
    uint256 internal agreementId;

    event DisputeRaised(uint256 indexed disputeId, uint256 indexed agreementId, address indexed initiator);
    event EvidenceSubmitted(uint256 indexed disputeId, address indexed submitter, bytes32 evidenceHash);
    event JurorsSelected(uint256 indexed disputeId, address[] jurors);
    event VoteCast(uint256 indexed disputeId, address indexed juror, bool favorInitiator);
    event DisputeResolved(uint256 indexed disputeId, bool favorInitiator, uint256 votesFor, uint256 votesAgainst);
    event DisputeAppealed(uint256 indexed disputeId, address indexed appellant);

    function setUp() public {
        mockWorldID = new MockWorldID();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        registry = new PliqRegistry(address(mockWorldID), Constants.ACTION_ID);
        staking = new StakingManager(address(registry), treasury);
        reputation = new ReputationAccumulator(address(registry));
        agreement = new RentalAgreement(address(registry), address(0), address(staking));
        dispute = new DisputeResolver(address(agreement), address(staking), address(reputation));

        // Register users
        vm.prank(landlord);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_1, dummyProof);
        vm.prank(tenant);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_2, dummyProof);

        // Create listing + app + agreement
        vm.prank(landlord);
        uint256 listingId = registry.createListing(Constants.LISTING_HASH, Constants.DEPOSIT_AMOUNT, Constants.MONTHLY_RENT, Constants.METADATA_URI);
        vm.prank(tenant);
        uint256 appId = registry.applyForRental(listingId);
        vm.prank(landlord);
        registry.acceptApplication(appId);
        vm.prank(landlord);
        agreementId = agreement.createAgreement(listingId, appId, Constants.LEASE_HASH, uint64(block.timestamp) + 30 days, uint64(block.timestamp) + 395 days);

        // Deposit
        usdc.mint(tenant, 100_000e6);
        vm.startPrank(tenant);
        usdc.approve(address(agreement), Constants.DEPOSIT_AMOUNT);
        agreement.payDeposit(agreementId, address(usdc));
        vm.stopPrank();
    }

    // --- Raise Dispute ---

    function test_RaiseDispute_ByLandlord() public {
        vm.prank(landlord);
        uint256 disputeId = dispute.raiseDispute(agreementId, "Lease violation", Constants.EVIDENCE_HASH);

        assertEq(disputeId, 1);
        PliqTypes.Dispute memory d = dispute.getDisputeById(disputeId);
        assertEq(d.initiator, landlord);
        assertEq(d.respondent, tenant);
        assertEq(uint8(d.status), uint8(PliqTypes.DisputeStatus.EvidenceCollection));
    }

    function test_RaiseDispute_ByTenant() public {
        vm.prank(tenant);
        uint256 disputeId = dispute.raiseDispute(agreementId, "Bad conditions", Constants.EVIDENCE_HASH);

        PliqTypes.Dispute memory d = dispute.getDisputeById(disputeId);
        assertEq(d.initiator, tenant);
        assertEq(d.respondent, landlord);
    }

    function test_RaiseDispute_ByNonParty_Reverts() public {
        vm.prank(Constants.RANDOM_USER);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.NotAgreementParty.selector, Constants.RANDOM_USER));
        dispute.raiseDispute(agreementId, "Unauthorized", bytes32(0));
    }

    // --- Submit Evidence ---

    function test_SubmitEvidence_WithinDeadline() public {
        vm.prank(landlord);
        uint256 disputeId = dispute.raiseDispute(agreementId, "Violation", Constants.EVIDENCE_HASH);

        vm.prank(tenant);
        dispute.submitEvidence(disputeId, keccak256("counter-evidence"), "ipfs://counter");

        PliqTypes.Evidence[] memory evidence = dispute.getEvidence(disputeId);
        assertEq(evidence.length, 2); // Initial + submitted
    }

    function test_SubmitEvidence_AfterDeadline_Reverts() public {
        vm.prank(landlord);
        uint256 disputeId = dispute.raiseDispute(agreementId, "Violation", Constants.EVIDENCE_HASH);

        vm.warp(block.timestamp + 8 days);

        vm.prank(tenant);
        vm.expectRevert();
        dispute.submitEvidence(disputeId, keccak256("late"), "ipfs://late");
    }

    function test_SubmitEvidence_ByNonParty_Reverts() public {
        vm.prank(landlord);
        uint256 disputeId = dispute.raiseDispute(agreementId, "Violation", Constants.EVIDENCE_HASH);

        vm.prank(Constants.RANDOM_USER);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.NotDisputeParty.selector, Constants.RANDOM_USER));
        dispute.submitEvidence(disputeId, keccak256("x"), "");
    }

    // --- Select Jurors ---

    function test_SelectJurors() public {
        vm.prank(landlord);
        uint256 disputeId = dispute.raiseDispute(agreementId, "Violation", Constants.EVIDENCE_HASH);

        dispute.selectJurors(disputeId);

        address[] memory jurors = dispute.getJurors(disputeId);
        assertEq(jurors.length, 3);

        PliqTypes.Dispute memory d = dispute.getDisputeById(disputeId);
        assertEq(uint8(d.status), uint8(PliqTypes.DisputeStatus.Voting));
        assertGt(d.votingDeadline, 0);
    }

    // --- Cast Vote ---

    function test_CastVote_ByJuror() public {
        uint256 disputeId = _setupDispute();
        address[] memory jurors = dispute.getJurors(disputeId);

        vm.prank(jurors[0]);
        dispute.castVote(disputeId, true);

        assertTrue(dispute.hasVoted(disputeId, jurors[0]));

        PliqTypes.Dispute memory d = dispute.getDisputeById(disputeId);
        assertEq(d.totalVotesFor, 1);
    }

    function test_CastVote_ByNonJuror_Reverts() public {
        uint256 disputeId = _setupDispute();

        vm.prank(Constants.RANDOM_USER);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.NotSelectedJuror.selector, Constants.RANDOM_USER));
        dispute.castVote(disputeId, true);
    }

    function test_CastVote_Twice_Reverts() public {
        uint256 disputeId = _setupDispute();
        address[] memory jurors = dispute.getJurors(disputeId);

        vm.prank(jurors[0]);
        dispute.castVote(disputeId, true);

        vm.prank(jurors[0]);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.AlreadyVoted.selector, jurors[0]));
        dispute.castVote(disputeId, true);
    }

    // --- Resolve ---

    function test_ResolveDispute_InitiatorWins() public {
        uint256 disputeId = _setupDispute();
        address[] memory jurors = dispute.getJurors(disputeId);

        // All vote for initiator
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            dispute.castVote(disputeId, true);
        }

        dispute.resolveDispute(disputeId);

        PliqTypes.Dispute memory d = dispute.getDisputeById(disputeId);
        assertEq(uint8(d.status), uint8(PliqTypes.DisputeStatus.Resolved));
        assertGt(d.totalVotesFor, d.totalVotesAgainst);
    }

    function test_ResolveDispute_RespondentWins() public {
        uint256 disputeId = _setupDispute();
        address[] memory jurors = dispute.getJurors(disputeId);

        // All vote against initiator
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            dispute.castVote(disputeId, false);
        }

        dispute.resolveDispute(disputeId);

        PliqTypes.Dispute memory d = dispute.getDisputeById(disputeId);
        assertEq(uint8(d.status), uint8(PliqTypes.DisputeStatus.Resolved));
        assertGt(d.totalVotesAgainst, d.totalVotesFor);
    }

    function test_ResolveDispute_BeforeAllVotes_BeforeDeadline_Reverts() public {
        uint256 disputeId = _setupDispute();
        address[] memory jurors = dispute.getJurors(disputeId);

        vm.prank(jurors[0]);
        dispute.castVote(disputeId, true);

        // Only 1 of 3 voted, deadline not passed
        vm.expectRevert();
        dispute.resolveDispute(disputeId);
    }

    function test_ResolveDispute_AfterDeadline_PartialVotes() public {
        uint256 disputeId = _setupDispute();
        address[] memory jurors = dispute.getJurors(disputeId);

        vm.prank(jurors[0]);
        dispute.castVote(disputeId, true);

        // Warp past voting deadline
        vm.warp(block.timestamp + 6 days);
        dispute.resolveDispute(disputeId);

        PliqTypes.Dispute memory d = dispute.getDisputeById(disputeId);
        assertEq(uint8(d.status), uint8(PliqTypes.DisputeStatus.Resolved));
    }

    // --- Appeal ---

    function test_Appeal_WithinWindow() public {
        uint256 disputeId = _resolveDispute();

        vm.prank(tenant);
        dispute.appeal(disputeId);

        PliqTypes.Dispute memory d = dispute.getDisputeById(disputeId);
        assertEq(uint8(d.status), uint8(PliqTypes.DisputeStatus.Appealed));
    }

    function test_Appeal_AfterWindow_Reverts() public {
        uint256 disputeId = _resolveDispute();

        vm.warp(block.timestamp + 3 days);

        vm.prank(tenant);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.AppealWindowExpired.selector));
        dispute.appeal(disputeId);
    }

    function test_Appeal_ByNonParty_Reverts() public {
        uint256 disputeId = _resolveDispute();

        vm.prank(Constants.RANDOM_USER);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.NotDisputeParty.selector, Constants.RANDOM_USER));
        dispute.appeal(disputeId);
    }

    // --- Full Lifecycle ---

    function test_FullLifecycle() public {
        // 1. Raise
        vm.prank(landlord);
        uint256 disputeId = dispute.raiseDispute(agreementId, "Violation", Constants.EVIDENCE_HASH);

        // 2. Evidence
        vm.prank(tenant);
        dispute.submitEvidence(disputeId, keccak256("defense"), "ipfs://defense");

        // 3. Jurors
        dispute.selectJurors(disputeId);

        // 4. Vote
        address[] memory jurors = dispute.getJurors(disputeId);
        vm.prank(jurors[0]);
        dispute.castVote(disputeId, true);
        vm.prank(jurors[1]);
        dispute.castVote(disputeId, true);
        vm.prank(jurors[2]);
        dispute.castVote(disputeId, false);

        // 5. Resolve
        dispute.resolveDispute(disputeId);

        PliqTypes.Dispute memory d = dispute.getDisputeById(disputeId);
        assertEq(uint8(d.status), uint8(PliqTypes.DisputeStatus.Resolved));
        assertEq(d.totalVotesFor, 2);
        assertEq(d.totalVotesAgainst, 1);
    }

    // --- Admin ---

    function test_SetEvidenceDeadlineDays() public {
        dispute.setEvidenceDeadlineDays(14);
        assertEq(dispute.evidenceDeadlineDays(), 14);
    }

    function test_SetJurorCount() public {
        dispute.setJurorCount(5);
        assertEq(dispute.jurorCount(), 5);
    }

    // --- View ---

    function test_GetDisputesByAgreement() public {
        vm.prank(landlord);
        dispute.raiseDispute(agreementId, "Issue 1", bytes32(0));

        uint256[] memory ids = dispute.getDisputesByAgreement(agreementId);
        assertEq(ids.length, 1);
    }

    // --- Helpers ---

    function _setupDispute() internal returns (uint256 disputeId) {
        vm.prank(landlord);
        disputeId = dispute.raiseDispute(agreementId, "Violation", Constants.EVIDENCE_HASH);
        dispute.selectJurors(disputeId);
    }

    function _resolveDispute() internal returns (uint256 disputeId) {
        disputeId = _setupDispute();
        address[] memory jurors = dispute.getJurors(disputeId);
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            dispute.castVote(disputeId, true);
        }
        dispute.resolveDispute(disputeId);
    }
}
