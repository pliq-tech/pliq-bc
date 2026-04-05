// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/PliqTypes.sol";
import "./libraries/PliqErrors.sol";
import "./interfaces/IPliqRegistry.sol";

/// @title RentalAgreement - Manages rental agreement lifecycle
/// @notice Handles deposits, rent payments, move-in/out, and deposit release
contract RentalAgreement is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant DISPUTE_RESOLVER_ROLE = keccak256("DISPUTE_RESOLVER_ROLE");

    IPliqRegistry public registry;
    address public paymentRouter;
    address public stakingManager;

    mapping(uint256 => PliqTypes.Agreement) private _agreements;
    mapping(uint256 => address) private _agreementTokens;
    mapping(uint256 => uint128) private _escrowBalances;
    mapping(address => uint256[]) private _landlordAgreements;
    mapping(address => uint256[]) private _tenantAgreements;
    uint256 public agreementCount;

    event AgreementCreated(uint256 indexed agreementId, address indexed landlord, address indexed tenant, uint256 listingId);
    event DepositPaid(uint256 indexed agreementId, uint128 amount, address token);
    event RentPaid(uint256 indexed agreementId, uint128 amount, address token, uint64 timestamp);
    event MoveInConfirmed(uint256 indexed agreementId, address indexed confirmer, bytes32 conditionReportHash);
    event MoveOutInitiated(uint256 indexed agreementId, address indexed initiator);
    event MoveOutConfirmed(uint256 indexed agreementId, address indexed confirmer, bytes32 conditionReportHash);
    event DepositReleased(uint256 indexed agreementId, uint128 toTenant, uint128 toLandlord);
    event AgreementTerminated(uint256 indexed agreementId, string reason);
    event DepositDisputed(uint256 indexed agreementId, address indexed disputer);

    constructor(address _registry, address _paymentRouter, address _stakingManager) {
        if (_registry == address(0)) revert PliqErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        registry = IPliqRegistry(_registry);
        paymentRouter = _paymentRouter;
        stakingManager = _stakingManager;
    }

    /// @notice Create a new rental agreement from an accepted application
    function createAgreement(
        uint256 listingId,
        uint256 applicationId,
        bytes32 leaseHash,
        uint64 startDate,
        uint64 endDate
    ) external whenNotPaused returns (uint256) {
        PliqTypes.Listing memory listing = registry.getListingById(listingId);
        if (listing.owner != msg.sender) revert PliqErrors.NotListingOwner(msg.sender, listing.owner);

        PliqTypes.Application memory app = registry.getApplicationById(applicationId);
        if (app.status != PliqTypes.ApplicationStatus.Accepted) {
            revert PliqErrors.InvalidApplicationStatus(uint8(app.status), uint8(PliqTypes.ApplicationStatus.Accepted));
        }

        agreementCount++;
        _agreements[agreementCount] = PliqTypes.Agreement({
            landlord: msg.sender,
            tenant: app.applicant,
            listingId: listingId,
            leaseHash: leaseHash,
            startDate: startDate,
            endDate: endDate,
            deposit: listing.deposit,
            monthlyRent: listing.monthlyRent,
            status: PliqTypes.AgreementStatus.Created,
            checkInReportHash: bytes32(0),
            checkOutReportHash: bytes32(0),
            landlordConfirmedMoveIn: false,
            tenantConfirmedMoveIn: false,
            createdAt: uint64(block.timestamp)
        });

        _landlordAgreements[msg.sender].push(agreementCount);
        _tenantAgreements[app.applicant].push(agreementCount);

        emit AgreementCreated(agreementCount, msg.sender, app.applicant, listingId);
        return agreementCount;
    }

    /// @notice Pay the deposit to activate the agreement
    function payDeposit(uint256 agreementId, address token) external nonReentrant whenNotPaused {
        PliqTypes.Agreement storage a = _agreements[agreementId];
        if (a.createdAt == 0) revert PliqErrors.AgreementNotFound(agreementId);
        if (a.status != PliqTypes.AgreementStatus.Created) revert PliqErrors.InvalidAgreementStatus(uint8(a.status), uint8(PliqTypes.AgreementStatus.Created));
        if (msg.sender != a.tenant) revert PliqErrors.NotTenant(msg.sender, a.tenant);

        IERC20(token).safeTransferFrom(msg.sender, address(this), a.deposit);
        _agreementTokens[agreementId] = token;
        _escrowBalances[agreementId] = a.deposit;
        a.status = PliqTypes.AgreementStatus.DepositPaid;

        emit DepositPaid(agreementId, a.deposit, token);
    }

    /// @notice Pay monthly rent
    function payRent(uint256 agreementId, address token) external nonReentrant whenNotPaused {
        PliqTypes.Agreement storage a = _agreements[agreementId];
        if (a.status != PliqTypes.AgreementStatus.Active && a.status != PliqTypes.AgreementStatus.MoveInComplete) {
            revert PliqErrors.InvalidAgreementStatus(uint8(a.status), uint8(PliqTypes.AgreementStatus.Active));
        }
        if (msg.sender != a.tenant) revert PliqErrors.NotTenant(msg.sender, a.tenant);

        IERC20(token).safeTransferFrom(msg.sender, a.landlord, a.monthlyRent);
        emit RentPaid(agreementId, a.monthlyRent, token, uint64(block.timestamp));
    }

    /// @notice Confirm move-in (both parties must confirm)
    function confirmMoveIn(uint256 agreementId, bytes32 conditionReportHash) external whenNotPaused {
        PliqTypes.Agreement storage a = _agreements[agreementId];
        if (a.status != PliqTypes.AgreementStatus.DepositPaid && a.status != PliqTypes.AgreementStatus.Active) {
            revert PliqErrors.InvalidAgreementStatus(uint8(a.status), uint8(PliqTypes.AgreementStatus.DepositPaid));
        }

        if (msg.sender == a.landlord) {
            a.landlordConfirmedMoveIn = true;
            a.checkInReportHash = conditionReportHash;
        } else if (msg.sender == a.tenant) {
            a.tenantConfirmedMoveIn = true;
        } else {
            revert PliqErrors.NotAgreementParty(msg.sender);
        }

        if (a.landlordConfirmedMoveIn && a.tenantConfirmedMoveIn) {
            a.status = PliqTypes.AgreementStatus.MoveInComplete;
        } else if (a.status == PliqTypes.AgreementStatus.DepositPaid) {
            a.status = PliqTypes.AgreementStatus.Active;
        }

        emit MoveInConfirmed(agreementId, msg.sender, conditionReportHash);
    }

    /// @notice Initiate move-out process
    function initiateMoveOut(uint256 agreementId) external whenNotPaused {
        PliqTypes.Agreement storage a = _agreements[agreementId];
        if (a.status != PliqTypes.AgreementStatus.MoveInComplete && a.status != PliqTypes.AgreementStatus.Active) {
            revert PliqErrors.InvalidAgreementStatus(uint8(a.status), uint8(PliqTypes.AgreementStatus.MoveInComplete));
        }
        if (msg.sender != a.tenant && msg.sender != a.landlord) revert PliqErrors.NotAgreementParty(msg.sender);

        a.status = PliqTypes.AgreementStatus.MoveOutInitiated;
        emit MoveOutInitiated(agreementId, msg.sender);
    }

    /// @notice Confirm move-out with checkout condition report
    function confirmMoveOut(uint256 agreementId, bytes32 conditionReportHash) external whenNotPaused {
        PliqTypes.Agreement storage a = _agreements[agreementId];
        if (a.status != PliqTypes.AgreementStatus.MoveOutInitiated) {
            revert PliqErrors.InvalidAgreementStatus(uint8(a.status), uint8(PliqTypes.AgreementStatus.MoveOutInitiated));
        }
        if (msg.sender != a.tenant && msg.sender != a.landlord) revert PliqErrors.NotAgreementParty(msg.sender);

        a.checkOutReportHash = conditionReportHash;
        a.status = PliqTypes.AgreementStatus.MoveOutComplete;
        emit MoveOutConfirmed(agreementId, msg.sender, conditionReportHash);
    }

    /// @notice Release deposit back to tenant with optional deduction
    function releaseDeposit(uint256 agreementId, uint128 deduction) external nonReentrant whenNotPaused {
        PliqTypes.Agreement storage a = _agreements[agreementId];
        if (a.status != PliqTypes.AgreementStatus.MoveOutComplete) {
            revert PliqErrors.InvalidAgreementStatus(uint8(a.status), uint8(PliqTypes.AgreementStatus.MoveOutComplete));
        }
        if (msg.sender != a.landlord) revert PliqErrors.NotLandlord(msg.sender, a.landlord);
        if (deduction > _escrowBalances[agreementId]) revert PliqErrors.DeductionExceedsDeposit(deduction, _escrowBalances[agreementId]);

        uint128 escrow = _escrowBalances[agreementId];
        uint128 toTenant = escrow - deduction;
        _escrowBalances[agreementId] = 0;

        IERC20 token = IERC20(_agreementTokens[agreementId]);
        if (toTenant > 0) token.safeTransfer(a.tenant, toTenant);
        if (deduction > 0) token.safeTransfer(a.landlord, deduction);

        a.status = PliqTypes.AgreementStatus.Terminated;
        emit DepositReleased(agreementId, toTenant, deduction);
    }

    /// @notice Tenant disputes a deduction
    function disputeDeduction(uint256 agreementId) external whenNotPaused {
        PliqTypes.Agreement storage a = _agreements[agreementId];
        if (msg.sender != a.tenant) revert PliqErrors.NotTenant(msg.sender, a.tenant);
        if (a.status != PliqTypes.AgreementStatus.MoveOutComplete) {
            revert PliqErrors.InvalidAgreementStatus(uint8(a.status), uint8(PliqTypes.AgreementStatus.MoveOutComplete));
        }

        a.status = PliqTypes.AgreementStatus.Disputed;
        emit DepositDisputed(agreementId, msg.sender);
    }

    /// @notice Terminate agreement early
    function terminateEarly(uint256 agreementId, string calldata reason) external whenNotPaused {
        PliqTypes.Agreement storage a = _agreements[agreementId];
        if (msg.sender != a.tenant && msg.sender != a.landlord) revert PliqErrors.NotAgreementParty(msg.sender);
        a.status = PliqTypes.AgreementStatus.Terminated;
        emit AgreementTerminated(agreementId, reason);
    }

    // View functions
    function getAgreementById(uint256 id) external view returns (PliqTypes.Agreement memory) { return _agreements[id]; }
    function getEscrowBalance(uint256 agreementId) external view returns (uint128) { return _escrowBalances[agreementId]; }
    function getAgreementsByLandlord(address landlord) external view returns (uint256[] memory) { return _landlordAgreements[landlord]; }
    function getAgreementsByTenant(address tenant) external view returns (uint256[] memory) { return _tenantAgreements[tenant]; }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
