// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/StakingManager.sol";
import "../src/PliqRegistry.sol";
import "../src/libraries/PliqTypes.sol";
import "../src/libraries/PliqErrors.sol";
import "./helpers/MockWorldID.sol";
import "./helpers/MockERC20.sol";
import "./helpers/Constants.sol";

contract StakingManagerTest is Test {
    StakingManager internal staking;
    PliqRegistry internal registry;
    MockWorldID internal mockWorldID;
    MockERC20 internal usdc;

    address internal admin = address(this);
    address internal staker = Constants.TENANT;
    address internal treasury = Constants.TREASURY;

    uint256[8] internal dummyProof;

    event StakeCreated(uint256 indexed stakeId, address indexed staker, PliqTypes.StakeType stakeType, uint128 amount);
    event StakeReleased(uint256 indexed stakeId, address indexed staker, uint128 amount);
    event StakeSlashed(uint256 indexed stakeId, address indexed staker, uint128 amount, string reason);

    function setUp() public {
        mockWorldID = new MockWorldID();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        registry = new PliqRegistry(address(mockWorldID), Constants.ACTION_ID);
        staking = new StakingManager(address(registry), treasury);

        // Register staker
        vm.prank(staker);
        registry.registerUser(Constants.ROOT, Constants.NULLIFIER_1, dummyProof);

        // Mint and approve
        usdc.mint(staker, 100_000e6);
        vm.prank(staker);
        usdc.approve(address(staking), type(uint256).max);
    }

    // --- Stake ---

    function test_StakeToList_Success() public {
        vm.prank(staker);
        uint256 stakeId = staking.stakeToList(1, Constants.STAKE_AMOUNT, address(usdc));

        assertEq(stakeId, 1);
        PliqTypes.Stake memory s = staking.getStakeById(stakeId);
        assertEq(s.staker, staker);
        assertEq(s.amount, Constants.STAKE_AMOUNT);
        assertEq(uint8(s.stakeType), uint8(PliqTypes.StakeType.Listing));
        assertEq(uint8(s.status), uint8(PliqTypes.StakeStatus.Active));
    }

    function test_StakeToVisit_Success() public {
        vm.prank(staker);
        uint256 stakeId = staking.stakeToVisit(1, 10e6, address(usdc));

        PliqTypes.Stake memory s = staking.getStakeById(stakeId);
        assertEq(uint8(s.stakeType), uint8(PliqTypes.StakeType.Visit));
    }

    function test_StakeToRent_Success() public {
        vm.prank(staker);
        uint256 stakeId = staking.stakeToRent(1, Constants.STAKE_AMOUNT, address(usdc));

        PliqTypes.Stake memory s = staking.getStakeById(stakeId);
        assertEq(uint8(s.stakeType), uint8(PliqTypes.StakeType.Rent));
    }

    function test_Stake_BelowMinimum_Reverts() public {
        vm.prank(staker);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.InsufficientStakeAmount.selector, uint128(1e6), uint128(50e6)));
        staking.stakeToList(1, 1e6, address(usdc));
    }

    function test_Stake_Unregistered_Reverts() public {
        usdc.mint(Constants.RANDOM_USER, 100e6);
        vm.startPrank(Constants.RANDOM_USER);
        usdc.approve(address(staking), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.NotRegistered.selector, Constants.RANDOM_USER));
        staking.stakeToList(1, Constants.STAKE_AMOUNT, address(usdc));
        vm.stopPrank();
    }

    function test_Stake_ZeroAmount_Reverts() public {
        vm.prank(staker);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.ZeroAmount.selector));
        staking.stakeToList(1, 0, address(usdc));
    }

    // --- Slash ---

    function test_Slash_ByOperator() public {
        vm.prank(staker);
        uint256 stakeId = staking.stakeToList(1, Constants.STAKE_AMOUNT, address(usdc));

        uint128 slashAmount = 30e6;
        uint256 treasuryBal = usdc.balanceOf(treasury);

        staking.slash(stakeId, slashAmount, "Listing misrepresentation");

        PliqTypes.Stake memory s = staking.getStakeById(stakeId);
        assertEq(s.amount, Constants.STAKE_AMOUNT - slashAmount);
        assertEq(uint8(s.status), uint8(PliqTypes.StakeStatus.PartiallySlashed));
        assertEq(usdc.balanceOf(treasury), treasuryBal + slashAmount);
    }

    function test_Slash_FullAmount() public {
        vm.prank(staker);
        uint256 stakeId = staking.stakeToList(1, Constants.STAKE_AMOUNT, address(usdc));

        staking.slash(stakeId, Constants.STAKE_AMOUNT, "Full slash");

        PliqTypes.Stake memory s = staking.getStakeById(stakeId);
        assertEq(s.amount, 0);
        assertEq(uint8(s.status), uint8(PliqTypes.StakeStatus.Slashed));
    }

    function test_Slash_ExceedsStake_Reverts() public {
        vm.prank(staker);
        uint256 stakeId = staking.stakeToList(1, Constants.STAKE_AMOUNT, address(usdc));

        vm.expectRevert(abi.encodeWithSelector(PliqErrors.SlashExceedsStake.selector, Constants.STAKE_AMOUNT + 1, Constants.STAKE_AMOUNT));
        staking.slash(stakeId, Constants.STAKE_AMOUNT + 1, "Too much");
    }

    function test_Slash_ByUnauthorized_Reverts() public {
        vm.prank(staker);
        uint256 stakeId = staking.stakeToList(1, Constants.STAKE_AMOUNT, address(usdc));

        vm.prank(staker);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.Unauthorized.selector, staker));
        staking.slash(stakeId, 10e6, "Unauthorized");
    }

    // --- Release ---

    function test_ReleaseStake_ByStaker() public {
        vm.prank(staker);
        uint256 stakeId = staking.stakeToList(1, Constants.STAKE_AMOUNT, address(usdc));

        uint256 stakerBal = usdc.balanceOf(staker);
        vm.prank(staker);
        staking.releaseStake(stakeId);

        PliqTypes.Stake memory s = staking.getStakeById(stakeId);
        assertEq(uint8(s.status), uint8(PliqTypes.StakeStatus.Released));
        assertEq(usdc.balanceOf(staker), stakerBal + Constants.STAKE_AMOUNT);
    }

    function test_ReleaseStake_AlreadyReleased_Reverts() public {
        vm.prank(staker);
        uint256 stakeId = staking.stakeToList(1, Constants.STAKE_AMOUNT, address(usdc));

        vm.prank(staker);
        staking.releaseStake(stakeId);

        vm.prank(staker);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.StakeAlreadyReleased.selector, stakeId));
        staking.releaseStake(stakeId);
    }

    function test_PartialSlash_ThenRelease() public {
        vm.prank(staker);
        uint256 stakeId = staking.stakeToList(1, Constants.STAKE_AMOUNT, address(usdc));

        staking.slash(stakeId, 30e6, "Partial");

        uint256 stakerBal = usdc.balanceOf(staker);
        vm.prank(staker);
        staking.releaseStake(stakeId);

        assertEq(usdc.balanceOf(staker), stakerBal + (Constants.STAKE_AMOUNT - 30e6));
    }

    // --- Admin ---

    function test_SetMinimumStake() public {
        staking.setMinimumStake(PliqTypes.StakeType.Listing, 100e6);
        assertEq(staking.getMinimumStake(PliqTypes.StakeType.Listing), 100e6);
    }

    function test_SetMinimumStake_ByNonAdmin_Reverts() public {
        vm.prank(staker);
        vm.expectRevert();
        staking.setMinimumStake(PliqTypes.StakeType.Listing, 100e6);
    }

    function test_SetTreasury() public {
        address newTreasury = address(0x999);
        staking.setTreasuryAddress(newTreasury);
        assertEq(staking.treasury(), newTreasury);
    }

    // --- View ---

    function test_GetStakesByUser() public {
        vm.prank(staker);
        staking.stakeToList(1, Constants.STAKE_AMOUNT, address(usdc));
        vm.prank(staker);
        staking.stakeToVisit(2, 10e6, address(usdc));

        uint256[] memory ids = staking.getStakesByUser(staker);
        assertEq(ids.length, 2);
    }
}
