// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/PliqTypes.sol";

interface IPaymentRouter {
    // Write
    function processPayment(uint256 agreementId, uint128 amount, address token) external;
    function setupRecurringPayment(
        uint256 agreementId,
        uint128 amount,
        address token,
        uint32 intervalDays
    ) external returns (uint256 scheduleId);
    function executeRecurringPayment(uint256 scheduleId) external;
    function cancelRecurringPayment(uint256 scheduleId) external;
    function setUnlinkRoute(uint256 agreementId, bytes calldata unlinkConfig) external;
    function bridgePayment(
        uint256 agreementId,
        uint32 destinationDomain,
        address recipient,
        uint128 amount
    ) external;

    // Admin
    function setPlatformFee(uint16 feeBasisPoints) external;
    function setFeeRecipient(address recipient) external;
    function addSupportedToken(address token) external;
    function removeSupportedToken(address token) external;
    function setCCTPEnabled(bool enabled) external;

    // Read
    function getPaymentHistory(uint256 agreementId) external view returns (PliqTypes.Payment[] memory);
    function getRecurringSchedule(uint256 agreementId) external view returns (PliqTypes.RecurringSchedule memory);
    function getSupportedTokens() external view returns (address[] memory);
    function getPlatformFee() external view returns (uint16);

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
}
