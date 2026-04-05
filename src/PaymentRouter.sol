// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/PliqTypes.sol";
import "./libraries/PliqErrors.sol";

/// @title PaymentRouter - Fee routing, recurring payments, CCTP bridge, token allowlist
/// @notice Routes payments with platform fee, manages recurring schedules, supports cross-chain via CCTP
contract PaymentRouter is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    uint16 public constant MAX_FEE_BPS = 1000; // 10% cap

    address public feeRecipient;
    uint16 public platformFeeBps = 250; // 2.5% default
    bool public cctpEnabled;

    mapping(address => bool) private _supportedTokens;
    address[] private _tokenList;

    mapping(uint256 => PliqTypes.RecurringSchedule) private _schedules;
    mapping(uint256 => PliqTypes.Payment[]) private _paymentHistory;
    mapping(uint256 => bytes) private _unlinkConfigs;
    uint256 public scheduleCount;

    // Events
    event PaymentProcessed(uint256 indexed agreementId, uint128 amount, address token, uint128 fee);
    event RecurringPaymentSetup(uint256 indexed scheduleId, uint256 indexed agreementId, uint128 amount, uint32 intervalDays);
    event RecurringPaymentExecuted(uint256 indexed scheduleId, uint128 amount);
    event RecurringPaymentCancelled(uint256 indexed scheduleId);
    event UnlinkRouteConfigured(uint256 indexed agreementId);
    event BridgeInitiated(uint256 indexed agreementId, uint32 destinationDomain, uint128 amount);
    event PlatformFeeUpdated(uint16 newFeeBps);
    event SupportedTokenAdded(address indexed token);
    event SupportedTokenRemoved(address indexed token);

    constructor(address _feeRecipient) {
        if (_feeRecipient == address(0)) revert PliqErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(KEEPER_ROLE, msg.sender);
        feeRecipient = _feeRecipient;
    }

    /// @notice Process a one-time payment with platform fee deduction
    function processPayment(
        uint256 agreementId,
        uint128 amount,
        address token
    ) external nonReentrant whenNotPaused {
        if (amount == 0) revert PliqErrors.ZeroAmount();
        if (!_supportedTokens[token]) revert PliqErrors.TokenNotSupported(token);

        uint128 fee = (amount * platformFeeBps) / 10_000;
        uint128 netAmount = amount - fee;

        // Transfer net amount to caller (the RentalAgreement routes to landlord)
        // In practice, the caller specifies the recipient via the agreement
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Fee to platform
        if (fee > 0) {
            IERC20(token).safeTransfer(feeRecipient, fee);
        }

        // Net to caller (will be the landlord address in integration)
        if (netAmount > 0) {
            IERC20(token).safeTransfer(msg.sender, netAmount);
        }

        _paymentHistory[agreementId].push(PliqTypes.Payment({
            agreementId: agreementId,
            amount: amount,
            token: token,
            status: PliqTypes.PaymentStatus.Completed,
            timestamp: uint64(block.timestamp)
        }));

        emit PaymentProcessed(agreementId, amount, token, fee);
    }

    /// @notice Setup a recurring payment schedule
    function setupRecurringPayment(
        uint256 agreementId,
        uint128 amount,
        address token,
        uint32 intervalDays
    ) external whenNotPaused returns (uint256) {
        if (amount == 0) revert PliqErrors.ZeroAmount();
        if (!_supportedTokens[token]) revert PliqErrors.TokenNotSupported(token);

        scheduleCount++;
        _schedules[scheduleCount] = PliqTypes.RecurringSchedule({
            agreementId: agreementId,
            amount: amount,
            token: token,
            intervalDays: intervalDays,
            nextPaymentDate: uint64(block.timestamp) + uint64(intervalDays) * 1 days,
            active: true
        });

        emit RecurringPaymentSetup(scheduleCount, agreementId, amount, intervalDays);
        return scheduleCount;
    }

    /// @notice Execute a due recurring payment (KEEPER_ROLE only)
    function executeRecurringPayment(uint256 scheduleId) external onlyRole(KEEPER_ROLE) nonReentrant whenNotPaused {
        PliqTypes.RecurringSchedule storage s = _schedules[scheduleId];
        if (!s.active) revert PliqErrors.ScheduleNotActive(scheduleId);
        if (block.timestamp < s.nextPaymentDate) revert PliqErrors.RecurringNotDue(scheduleId, s.nextPaymentDate);

        s.nextPaymentDate = s.nextPaymentDate + uint64(s.intervalDays) * 1 days;
        emit RecurringPaymentExecuted(scheduleId, s.amount);
    }

    /// @notice Cancel a recurring payment schedule
    function cancelRecurringPayment(uint256 scheduleId) external whenNotPaused {
        PliqTypes.RecurringSchedule storage s = _schedules[scheduleId];
        if (!s.active) revert PliqErrors.ScheduleNotActive(scheduleId);
        s.active = false;
        emit RecurringPaymentCancelled(scheduleId);
    }

    /// @notice Configure Unlink routing for an agreement (placeholder)
    function setUnlinkRoute(uint256 agreementId, bytes calldata unlinkConfig) external onlyRole(OPERATOR_ROLE) {
        _unlinkConfigs[agreementId] = unlinkConfig;
        emit UnlinkRouteConfigured(agreementId);
    }

    /// @notice Initiate a CCTP cross-chain bridge payment (behind feature flag)
    function bridgePayment(
        uint256 agreementId,
        uint32 destinationDomain,
        address recipient,
        uint128 amount
    ) external nonReentrant whenNotPaused {
        if (!cctpEnabled) revert PliqErrors.CCTPDisabled();
        if (amount == 0) revert PliqErrors.ZeroAmount();
        if (recipient == address(0)) revert PliqErrors.ZeroAddress();

        // Placeholder: actual CCTP TokenMessenger.depositForBurn() call would go here
        emit BridgeInitiated(agreementId, destinationDomain, amount);
    }

    // Admin functions
    function setPlatformFee(uint16 feeBasisPoints) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (feeBasisPoints > MAX_FEE_BPS) revert PliqErrors.FeeTooHigh(feeBasisPoints, MAX_FEE_BPS);
        platformFeeBps = feeBasisPoints;
        emit PlatformFeeUpdated(feeBasisPoints);
    }

    function setFeeRecipient(address recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) revert PliqErrors.ZeroAddress();
        feeRecipient = recipient;
    }

    function addSupportedToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) revert PliqErrors.ZeroAddress();
        if (!_supportedTokens[token]) {
            _supportedTokens[token] = true;
            _tokenList.push(token);
            emit SupportedTokenAdded(token);
        }
    }

    function removeSupportedToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_supportedTokens[token]) {
            _supportedTokens[token] = false;
            // Remove from list
            for (uint256 i = 0; i < _tokenList.length; i++) {
                if (_tokenList[i] == token) {
                    _tokenList[i] = _tokenList[_tokenList.length - 1];
                    _tokenList.pop();
                    break;
                }
            }
            emit SupportedTokenRemoved(token);
        }
    }

    function setCCTPEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        cctpEnabled = enabled;
    }

    // View functions
    function getPaymentHistory(uint256 agreementId) external view returns (PliqTypes.Payment[] memory) {
        return _paymentHistory[agreementId];
    }

    function getRecurringSchedule(uint256 agreementId) external view returns (PliqTypes.RecurringSchedule memory) {
        // Find schedule by agreementId (linear search for simplicity)
        for (uint256 i = 1; i <= scheduleCount; i++) {
            if (_schedules[i].agreementId == agreementId) {
                return _schedules[i];
            }
        }
        return PliqTypes.RecurringSchedule(0, 0, address(0), 0, 0, false);
    }

    function getSupportedTokens() external view returns (address[] memory) { return _tokenList; }
    function getPlatformFee() external view returns (uint16) { return platformFeeBps; }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
