// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/PaymentRouter.sol";
import "../src/libraries/PliqTypes.sol";
import "../src/libraries/PliqErrors.sol";
import "./helpers/MockERC20.sol";
import "./helpers/Constants.sol";

contract PaymentRouterTest is Test {
    PaymentRouter internal router;
    MockERC20 internal usdc;

    address internal admin = address(this);
    address internal treasury = Constants.TREASURY;
    address internal payer = Constants.TENANT;

    event PaymentProcessed(uint256 indexed agreementId, uint128 amount, address token, uint128 fee);
    event RecurringPaymentSetup(uint256 indexed scheduleId, uint256 indexed agreementId, uint128 amount, uint32 intervalDays);
    event PlatformFeeUpdated(uint16 newFeeBps);

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        router = new PaymentRouter(treasury);
        router.addSupportedToken(address(usdc));

        usdc.mint(payer, 100_000e6);
        vm.prank(payer);
        usdc.approve(address(router), type(uint256).max);
    }

    // --- Process Payment ---

    function test_ProcessPayment_Success() public {
        uint128 amount = 1000e6;
        uint128 expectedFee = (amount * 250) / 10_000; // 2.5%
        uint256 treasuryBal = usdc.balanceOf(treasury);

        vm.prank(payer);
        router.processPayment(1, amount, address(usdc));

        assertEq(usdc.balanceOf(treasury), treasuryBal + expectedFee);
    }

    function test_ProcessPayment_UnsupportedToken_Reverts() public {
        address fakeToken = address(0xBEEF);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.TokenNotSupported.selector, fakeToken));
        router.processPayment(1, 1000e6, fakeToken);
    }

    function test_ProcessPayment_ZeroAmount_Reverts() public {
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.ZeroAmount.selector));
        router.processPayment(1, 0, address(usdc));
    }

    // --- Fee Calculation ---

    function test_FeeCalculation_250bps() public {
        uint128 amount = 10000e6;
        uint128 expectedFee = 250e6; // 2.5% of 10000

        uint256 treasuryBefore = usdc.balanceOf(treasury);
        vm.prank(payer);
        router.processPayment(1, amount, address(usdc));

        assertEq(usdc.balanceOf(treasury) - treasuryBefore, expectedFee);
    }

    function test_FeeCalculation_CustomFee() public {
        router.setPlatformFee(500); // 5%
        uint128 amount = 1000e6;
        uint128 expectedFee = 50e6;

        uint256 treasuryBefore = usdc.balanceOf(treasury);
        vm.prank(payer);
        router.processPayment(1, amount, address(usdc));

        assertEq(usdc.balanceOf(treasury) - treasuryBefore, expectedFee);
    }

    // --- Recurring Payments ---

    function test_SetupRecurringPayment() public {
        vm.prank(payer);
        uint256 scheduleId = router.setupRecurringPayment(1, Constants.MONTHLY_RENT, address(usdc), 30);

        assertEq(scheduleId, 1);
    }

    function test_ExecuteRecurringPayment_TooEarly_Reverts() public {
        vm.prank(payer);
        uint256 scheduleId = router.setupRecurringPayment(1, Constants.MONTHLY_RENT, address(usdc), 30);

        vm.expectRevert();
        router.executeRecurringPayment(scheduleId);
    }

    function test_ExecuteRecurringPayment_OnTime() public {
        vm.prank(payer);
        uint256 scheduleId = router.setupRecurringPayment(1, Constants.MONTHLY_RENT, address(usdc), 30);

        vm.warp(block.timestamp + 31 days);
        router.executeRecurringPayment(scheduleId);
    }

    function test_ExecuteRecurringPayment_NonKeeper_Reverts() public {
        vm.prank(payer);
        uint256 scheduleId = router.setupRecurringPayment(1, Constants.MONTHLY_RENT, address(usdc), 30);

        vm.warp(block.timestamp + 31 days);
        vm.prank(payer);
        vm.expectRevert();
        router.executeRecurringPayment(scheduleId);
    }

    function test_CancelRecurringPayment() public {
        vm.prank(payer);
        uint256 scheduleId = router.setupRecurringPayment(1, Constants.MONTHLY_RENT, address(usdc), 30);

        router.cancelRecurringPayment(scheduleId);
    }

    // --- Platform Fee ---

    function test_SetPlatformFee_WithinBounds() public {
        router.setPlatformFee(500);
        assertEq(router.getPlatformFee(), 500);
    }

    function test_SetPlatformFee_AboveMax_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.FeeTooHigh.selector, uint16(1001), uint16(1000)));
        router.setPlatformFee(1001);
    }

    function test_SetPlatformFee_NonAdmin_Reverts() public {
        vm.prank(payer);
        vm.expectRevert();
        router.setPlatformFee(500);
    }

    // --- Token Management ---

    function test_AddRemoveSupportedToken() public {
        MockERC20 eurc = new MockERC20("Euro Coin", "EURC", 6);
        router.addSupportedToken(address(eurc));

        address[] memory tokens = router.getSupportedTokens();
        assertEq(tokens.length, 2);

        router.removeSupportedToken(address(eurc));
        tokens = router.getSupportedTokens();
        assertEq(tokens.length, 1);
    }

    // --- CCTP ---

    function test_BridgePayment_Disabled_Reverts() public {
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(PliqErrors.CCTPDisabled.selector));
        router.bridgePayment(1, 6, payer, 1000e6);
    }

    function test_BridgePayment_Enabled() public {
        router.setCCTPEnabled(true);

        vm.prank(payer);
        router.bridgePayment(1, 6, payer, 1000e6);
    }

    // --- Payment History ---

    function test_GetPaymentHistory() public {
        vm.prank(payer);
        router.processPayment(1, 1000e6, address(usdc));

        PliqTypes.Payment[] memory history = router.getPaymentHistory(1);
        assertEq(history.length, 1);
        assertEq(history[0].amount, 1000e6);
    }
}
