// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/PliqTypes.sol";
import "./libraries/PliqErrors.sol";

/// @title RentalAgreement - Manages rental agreement lifecycle
/// @notice Handles deposits, rent payments, move-in/out, and deposit release
contract RentalAgreement is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    mapping(uint256 => PliqTypes.Agreement) private _agreements;
    uint256 public agreementCount;

    event AgreementCreated(uint256 indexed agreementId, address indexed landlord, address indexed tenant);
    event DepositPaid(uint256 indexed agreementId, uint128 amount);
    event RentPaid(uint256 indexed agreementId, uint128 amount);
    event MoveInConfirmed(uint256 indexed agreementId, address confirmer);
    event MoveOutInitiated(uint256 indexed agreementId);
    event DepositReleased(uint256 indexed agreementId, uint128 toTenant, uint128 toLandlord);
    event AgreementTerminated(uint256 indexed agreementId);

    constructor() { _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); }

    /// @notice Create a new rental agreement
    function createAgreement(address tenant, uint256 listingId, bytes32 leaseHash, uint64 startDate, uint64 endDate, uint128 deposit, uint128 monthlyRent, address paymentToken) external whenNotPaused returns (uint256) {
        if (tenant == address(0)) revert PliqErrors.ZeroAddress();
        agreementCount++;
        _agreements[agreementCount] = PliqTypes.Agreement({ landlord: msg.sender, tenant: tenant, listingId: listingId, leaseHash: leaseHash, startDate: startDate, endDate: endDate, deposit: deposit, monthlyRent: monthlyRent, status: PliqTypes.AgreementStatus.Created, paymentToken: paymentToken, checkInReportHash: bytes32(0), checkOutReportHash: bytes32(0), landlordConfirmedMoveIn: false, tenantConfirmedMoveIn: false, createdAt: uint64(block.timestamp) });
        emit AgreementCreated(agreementCount, msg.sender, tenant);
        return agreementCount;
    }

    /// @notice Pay the deposit to activate the agreement
    function payDeposit(uint256 agreementId) external nonReentrant whenNotPaused {
        PliqTypes.Agreement storage a = _agreements[agreementId];
        if (a.createdAt == 0) revert PliqErrors.AgreementNotFound(agreementId);
        if (a.status != PliqTypes.AgreementStatus.Created) revert PliqErrors.InvalidAgreementStatus(uint8(a.status), uint8(PliqTypes.AgreementStatus.Created));
        if (msg.sender != a.tenant) revert PliqErrors.NotTenant(msg.sender, a.tenant);
        IERC20(a.paymentToken).safeTransferFrom(msg.sender, address(this), a.deposit);
        a.status = PliqTypes.AgreementStatus.DepositPaid;
        emit DepositPaid(agreementId, a.deposit);
    }

    /// @notice Pay monthly rent
    function payRent(uint256 agreementId) external nonReentrant whenNotPaused {
        PliqTypes.Agreement storage a = _agreements[agreementId];
        if (a.status != PliqTypes.AgreementStatus.Active && a.status != PliqTypes.AgreementStatus.MoveInComplete) revert PliqErrors.InvalidAgreementStatus(uint8(a.status), uint8(PliqTypes.AgreementStatus.Active));
        if (msg.sender != a.tenant) revert PliqErrors.NotTenant(msg.sender, a.tenant);
        IERC20(a.paymentToken).safeTransferFrom(msg.sender, a.landlord, a.monthlyRent);
        emit RentPaid(agreementId, a.monthlyRent);
    }

    /// @notice Confirm move-in (both parties must confirm)
    function confirmMoveIn(uint256 agreementId, bytes32 conditionReportHash) external whenNotPaused {
        PliqTypes.Agreement storage a = _agreements[agreementId];
        if (a.status != PliqTypes.AgreementStatus.DepositPaid && a.status != PliqTypes.AgreementStatus.Active) revert PliqErrors.InvalidAgreementStatus(uint8(a.status), uint8(PliqTypes.AgreementStatus.DepositPaid));
        if (msg.sender == a.landlord) { a.landlordConfirmedMoveIn = true; a.checkInReportHash = conditionReportHash; }
        else if (msg.sender == a.tenant) { a.tenantConfirmedMoveIn = true; }
        else revert PliqErrors.NotAgreementParty(msg.sender);
        if (a.landlordConfirmedMoveIn && a.tenantConfirmedMoveIn) { a.status = PliqTypes.AgreementStatus.MoveInComplete; }
        else if (a.status == PliqTypes.AgreementStatus.DepositPaid) { a.status = PliqTypes.AgreementStatus.Active; }
        emit MoveInConfirmed(agreementId, msg.sender);
    }

    /// @notice Initiate move-out process
    function initiateMoveOut(uint256 agreementId) external whenNotPaused {
        PliqTypes.Agreement storage a = _agreements[agreementId];
        if (msg.sender != a.tenant && msg.sender != a.landlord) revert PliqErrors.NotAgreementParty(msg.sender);
        a.status = PliqTypes.AgreementStatus.MoveOutInitiated;
        emit MoveOutInitiated(agreementId);
    }

    /// @notice Release deposit back to tenant with optional deduction
    function releaseDeposit(uint256 agreementId, uint128 deduction) external nonReentrant whenNotPaused {
        PliqTypes.Agreement storage a = _agreements[agreementId];
        if (msg.sender != a.landlord) revert PliqErrors.NotLandlord(msg.sender, a.landlord);
        if (deduction > a.deposit) revert PliqErrors.DeductionExceedsDeposit(deduction, a.deposit);
        uint128 toTenant = a.deposit - deduction;
        IERC20 token = IERC20(a.paymentToken);
        if (toTenant > 0) token.safeTransfer(a.tenant, toTenant);
        if (deduction > 0) token.safeTransfer(a.landlord, deduction);
        a.status = PliqTypes.AgreementStatus.MoveOutComplete;
        emit DepositReleased(agreementId, toTenant, deduction);
    }

    /// @notice Terminate agreement early
    function terminateEarly(uint256 agreementId) external whenNotPaused {
        PliqTypes.Agreement storage a = _agreements[agreementId];
        if (msg.sender != a.tenant && msg.sender != a.landlord) revert PliqErrors.NotAgreementParty(msg.sender);
        a.status = PliqTypes.AgreementStatus.Terminated;
        emit AgreementTerminated(agreementId);
    }

    function getAgreementById(uint256 id) external view returns (PliqTypes.Agreement memory) { return _agreements[id]; }
    function getEscrowBalance(uint256 agreementId) external view returns (uint256) { PliqTypes.Agreement memory a = _agreements[agreementId]; return IERC20(a.paymentToken).balanceOf(address(this)); }
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
