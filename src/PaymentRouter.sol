// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/PliqTypes.sol";
import "./libraries/PliqErrors.sol";

/// @title PaymentRouter - Fee routing, recurring payment schedules, token allowlist
contract PaymentRouter is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint16 public constant MAX_FEE_BPS = 1000; // 10% cap

    mapping(address => bool) public supportedTokens;
    mapping(uint256 => PliqTypes.RecurringSchedule) private _schedules;
    uint256 public scheduleCount;
    uint16 public protocolFeeBps = 100; // 1% default
    address public treasury;

    event PaymentRouted(address indexed from, address indexed to, address token, uint128 amount, uint128 fee);
    event ScheduleCreated(uint256 indexed scheduleId, uint256 indexed agreementId, address indexed payer);
    event ScheduleExecuted(uint256 indexed scheduleId, uint128 amount);
    event ScheduleCancelled(uint256 indexed scheduleId);
    event TokenSupportUpdated(address indexed token, bool supported);
    event FeeUpdated(uint16 newFeeBps);

    constructor(address _treasury) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        treasury = _treasury;
    }

    /// @notice Route a one-time payment with protocol fee
    function routePayment(address token, address recipient, uint128 amount) external nonReentrant whenNotPaused {
        if (!supportedTokens[token]) revert PliqErrors.TokenNotSupported(token);
        if (amount == 0) revert PliqErrors.ZeroAmount();
        uint128 fee = (amount * protocolFeeBps) / 10_000;
        uint128 netAmount = amount - fee;
        IERC20(token).safeTransferFrom(msg.sender, recipient, netAmount);
        if (fee > 0) IERC20(token).safeTransferFrom(msg.sender, treasury, fee);
        emit PaymentRouted(msg.sender, recipient, token, netAmount, fee);
    }

    /// @notice Create a recurring payment schedule
    function createSchedule(uint256 agreementId, address recipient, uint128 amount, address token, uint32 intervalDays, uint64 firstPaymentDate) external whenNotPaused returns (uint256) {
        if (!supportedTokens[token]) revert PliqErrors.TokenNotSupported(token);
        if (amount == 0) revert PliqErrors.ZeroAmount();
        scheduleCount++;
        _schedules[scheduleCount] = PliqTypes.RecurringSchedule({ agreementId: agreementId, payer: msg.sender, recipient: recipient, amount: amount, token: token, intervalDays: intervalDays, nextPaymentDate: firstPaymentDate, active: true });
        emit ScheduleCreated(scheduleCount, agreementId, msg.sender);
        return scheduleCount;
    }

    /// @notice Execute a due recurring payment (operator or payer can trigger)
    function executeSchedule(uint256 scheduleId) external nonReentrant whenNotPaused {
        PliqTypes.RecurringSchedule storage s = _schedules[scheduleId];
        if (!s.active) revert PliqErrors.ZeroAmount(); // schedule inactive
        if (block.timestamp < s.nextPaymentDate) revert PliqErrors.ZeroAmount(); // not yet due
        if (msg.sender != s.payer && !hasRole(OPERATOR_ROLE, msg.sender)) revert PliqErrors.NotAgreementParty(msg.sender);
        uint128 fee = (s.amount * protocolFeeBps) / 10_000;
        uint128 netAmount = s.amount - fee;
        IERC20(s.token).safeTransferFrom(s.payer, s.recipient, netAmount);
        if (fee > 0) IERC20(s.token).safeTransferFrom(s.payer, treasury, fee);
        s.nextPaymentDate = s.nextPaymentDate + uint64(s.intervalDays) * 1 days;
        emit ScheduleExecuted(scheduleId, s.amount);
    }

    /// @notice Cancel a recurring schedule (payer or operator)
    function cancelSchedule(uint256 scheduleId) external whenNotPaused {
        PliqTypes.RecurringSchedule storage s = _schedules[scheduleId];
        if (msg.sender != s.payer && !hasRole(OPERATOR_ROLE, msg.sender)) revert PliqErrors.NotAgreementParty(msg.sender);
        s.active = false;
        emit ScheduleCancelled(scheduleId);
    }

    function getScheduleById(uint256 id) external view returns (PliqTypes.RecurringSchedule memory) { return _schedules[id]; }

    // Admin functions
    function setSupportedToken(address token, bool supported) external onlyRole(DEFAULT_ADMIN_ROLE) {
        supportedTokens[token] = supported;
        emit TokenSupportUpdated(token, supported);
    }

    function setProtocolFee(uint16 feeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (feeBps > MAX_FEE_BPS) revert PliqErrors.FeeTooHigh(feeBps, MAX_FEE_BPS);
        protocolFeeBps = feeBps;
        emit FeeUpdated(feeBps);
    }

    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) { treasury = _treasury; }
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
