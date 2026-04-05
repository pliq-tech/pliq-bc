// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/ReputationAccumulator.sol";
import "../src/PliqRegistry.sol";
import "../src/libraries/PliqTypes.sol";
import "../src/libraries/PliqErrors.sol";
import "./helpers/MockWorldID.sol";
import "./helpers/Constants.sol";

contract ReputationAccumulatorTest is Test {
    ReputationAccumulator internal accumulator;
    PliqRegistry internal registry;
    MockWorldID internal mockWorldID;

    address internal admin = address(this);
    address internal oracle = Constants.ORACLE;
    address internal user1 = Constants.TENANT;
    address internal user2 = Constants.LANDLORD;

    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    uint256[8] internal dummyProof;

    event ActionRecorded(address indexed user, PliqTypes.ActionType action, uint128 value);
    event SBTMinted(uint256 indexed tokenId, address indexed user, int256 score);
    event SBTUpdated(uint256 indexed tokenId, int256 newScore);
    event MerkleRootCommitted(bytes32 indexed root, uint64 timestamp);
    event Locked(uint256 indexed tokenId);

    function setUp() public {
        mockWorldID = new MockWorldID();
        registry = new PliqRegistry(address(mockWorldID), Constants.ACTION_ID);
        accumulator = new ReputationAccumulator(address(registry));
        accumulator.grantRole(ORACLE_ROLE, oracle);
    }

    // --- Record Action ---

    function test_RecordAction_Success() public {
        vm.expectEmit(true, false, false, true);
        emit ActionRecorded(user1, PliqTypes.ActionType.RentPaidOnTime, 100);

        accumulator.recordAction(user1, PliqTypes.ActionType.RentPaidOnTime, 100);

        PliqTypes.ReputationAction[] memory actions = accumulator.getActionHistory(user1);
        assertEq(actions.length, 1);
        assertEq(uint8(actions[0].actionType), uint8(PliqTypes.ActionType.RentPaidOnTime));
        assertEq(actions[0].value, 100);
    }

    function test_RecordAction_NonOperator_Reverts() public {
        vm.prank(user1);
        vm.expectRevert();
        accumulator.recordAction(user1, PliqTypes.ActionType.RentPaidOnTime, 100);
    }

    // --- Calculate Score ---

    function test_CalculateScore_PositiveActions() public {
        accumulator.recordAction(user1, PliqTypes.ActionType.RentPaidOnTime, 100);
        accumulator.recordAction(user1, PliqTypes.ActionType.PositiveReview, 50);

        int256 score = accumulator.calculateScore(user1);
        // RentPaidOnTime weight=10, value=100 -> 1000
        // PositiveReview weight=15, value=50 -> 750
        // Total: 1750
        assertEq(score, 1750);
    }

    function test_CalculateScore_NegativeActions() public {
        accumulator.recordAction(user1, PliqTypes.ActionType.RentPaidOnTime, 100);
        accumulator.recordAction(user1, PliqTypes.ActionType.RentPaidLate, 50);

        int256 score = accumulator.calculateScore(user1);
        // RentPaidOnTime: 10 * 100 = 1000
        // RentPaidLate: -5 * 50 = -250
        // Total: 750
        assertEq(score, 750);
    }

    function test_CalculateScore_Decay() public {
        accumulator.recordAction(user1, PliqTypes.ActionType.RentPaidOnTime, 100);

        int256 scoreBefore = accumulator.calculateScore(user1);

        // Warp past one half-life (90 days)
        vm.warp(block.timestamp + 91 days);

        int256 scoreAfter = accumulator.calculateScore(user1);
        // Score should be halved after one half-life
        assertEq(scoreAfter, scoreBefore / 2);
    }

    function test_CalculateScore_TwoHalfLives() public {
        accumulator.recordAction(user1, PliqTypes.ActionType.RentPaidOnTime, 100);

        int256 scoreBefore = accumulator.calculateScore(user1);

        // Warp past two half-lives
        vm.warp(block.timestamp + 181 days);

        int256 scoreAfter = accumulator.calculateScore(user1);
        assertEq(scoreAfter, scoreBefore / 4);
    }

    // --- Mint SBT ---

    function test_MintSBT_Success() public {
        uint256 tokenId = accumulator.mintReputationSBT(user1);

        assertEq(tokenId, 1);
        assertEq(accumulator.ownerOf(tokenId), user1);
        assertEq(accumulator.getTokenIdByUser(user1), tokenId);
    }

    function test_MintSBT_EmitsLocked() public {
        vm.expectEmit(true, false, false, false);
        emit Locked(1);

        accumulator.mintReputationSBT(user1);
    }

    function test_MintSBT_Duplicate_Reverts() public {
        accumulator.mintReputationSBT(user1);

        vm.expectRevert(abi.encodeWithSelector(PliqErrors.SBTAlreadyMinted.selector, user1));
        accumulator.mintReputationSBT(user1);
    }

    function test_TransferSBT_Reverts() public {
        accumulator.mintReputationSBT(user1);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.SoulboundTransferBlocked.selector));
        accumulator.transferFrom(user1, user2, 1);
    }

    // --- Update SBT ---

    function test_UpdateSBT() public {
        uint256 tokenId = accumulator.mintReputationSBT(user1);
        accumulator.recordAction(user1, PliqTypes.ActionType.RentPaidOnTime, 100);

        vm.expectEmit(true, false, false, true);
        emit SBTUpdated(tokenId, 1000);

        accumulator.updateSBT(tokenId);
    }

    // --- Merkle Root ---

    function test_CommitMerkleRoot_ByOracle() public {
        bytes32 root = keccak256("merkle-root");
        uint64 ts = uint64(block.timestamp);

        vm.expectEmit(true, false, false, true);
        emit MerkleRootCommitted(root, ts);

        vm.prank(oracle);
        accumulator.commitMerkleRoot(root, ts);

        (bytes32 storedRoot, uint64 storedTs) = accumulator.getLatestMerkleRoot();
        assertEq(storedRoot, root);
        assertEq(storedTs, ts);
    }

    function test_CommitMerkleRoot_NonOracle_Reverts() public {
        vm.prank(user1);
        vm.expectRevert();
        accumulator.commitMerkleRoot(keccak256("root"), uint64(block.timestamp));
    }

    // --- Merkle Proof ---

    function test_VerifyMerkleProof() public view {
        // Build a simple 2-leaf Merkle tree
        bytes32 leaf1 = keccak256(abi.encodePacked(user1, int256(100)));
        bytes32 leaf2 = keccak256(abi.encodePacked(user2, int256(200)));
        bytes32 root = leaf1 <= leaf2
            ? keccak256(abi.encodePacked(leaf1, leaf2))
            : keccak256(abi.encodePacked(leaf2, leaf1));

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leaf2;

        bool valid = accumulator.verifyMerkleProof(proof, leaf1, root);
        assertTrue(valid);
    }

    function test_VerifyMerkleProof_Invalid() public view {
        bytes32 root = keccak256("root");
        bytes32 leaf = keccak256("wrong-leaf");
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = keccak256("sibling");

        bool valid = accumulator.verifyMerkleProof(proof, leaf, root);
        assertFalse(valid);
    }

    // --- ERC-5192 ---

    function test_Locked_ReturnsTrue() public {
        accumulator.mintReputationSBT(user1);
        assertTrue(accumulator.locked(1));
    }

    function test_SupportsInterface_ERC5192() public view {
        assertTrue(accumulator.supportsInterface(0xb45a3c0e)); // ERC-5192
    }
}
