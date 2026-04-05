// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/PliqTypes.sol";
import "./libraries/PliqErrors.sol";

/// @title StakingManager - Protocol staking for listings, visits, and rentals
contract StakingManager is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    mapping(uint256 => PliqTypes.StakeInfo) private _stakes;
    uint256 public stakeCount;
    uint128 public minimumStake = 10e6; // 10 USDC (6 decimals)
    address public treasury;

    event Staked(uint256 indexed stakeId, address indexed staker, PliqTypes.StakeType stakeType, uint128 amount);
    event StakeSlashed(uint256 indexed stakeId, uint128 amount);
    event StakeReleased(uint256 indexed stakeId, uint128 amount);

    constructor(address _treasury) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        treasury = _treasury;
    }

    function _stake(PliqTypes.StakeType stakeType, uint128 amount, address token, uint256 referenceId) internal returns (uint256) {
        if (amount < minimumStake) revert PliqErrors.InsufficientStakeAmount(amount, minimumStake);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        stakeCount++;
        _stakes[stakeCount] = PliqTypes.StakeInfo({ staker: msg.sender, stakeType: stakeType, amount: amount, originalAmount: amount, token: token, referenceId: referenceId, status: PliqTypes.StakeStatus.Active, createdAt: uint64(block.timestamp) });
        emit Staked(stakeCount, msg.sender, stakeType, amount);
        return stakeCount;
    }

    function stakeToList(uint128 amount, address token, uint256 listingId) external nonReentrant whenNotPaused returns (uint256) { return _stake(PliqTypes.StakeType.Listing, amount, token, listingId); }
    function stakeToVisit(uint128 amount, address token, uint256 listingId) external nonReentrant whenNotPaused returns (uint256) { return _stake(PliqTypes.StakeType.Visit, amount, token, listingId); }
    function stakeToRent(uint128 amount, address token, uint256 agreementId) external nonReentrant whenNotPaused returns (uint256) { return _stake(PliqTypes.StakeType.Rent, amount, token, agreementId); }

    /// @notice Slash a stake (operator only)
    function slash(uint256 stakeId, uint128 amount) external onlyRole(OPERATOR_ROLE) nonReentrant {
        PliqTypes.StakeInfo storage s = _stakes[stakeId];
        if (s.status != PliqTypes.StakeStatus.Active && s.status != PliqTypes.StakeStatus.PartiallySlashed) revert PliqErrors.StakeNotActive(stakeId);
        if (amount > s.amount) revert PliqErrors.SlashExceedsStake(amount, s.amount);
        s.amount -= amount;
        s.status = s.amount == 0 ? PliqTypes.StakeStatus.Slashed : PliqTypes.StakeStatus.PartiallySlashed;
        IERC20(s.token).safeTransfer(treasury, amount);
        emit StakeSlashed(stakeId, amount);
    }

    /// @notice Release remaining stake back to staker
    function releaseStake(uint256 stakeId) external nonReentrant {
        PliqTypes.StakeInfo storage s = _stakes[stakeId];
        if (s.status == PliqTypes.StakeStatus.Released) revert PliqErrors.StakeAlreadyReleased(stakeId);
        if (msg.sender != s.staker && !hasRole(OPERATOR_ROLE, msg.sender)) revert PliqErrors.NotAgreementParty(msg.sender);
        uint128 refund = s.amount;
        s.amount = 0;
        s.status = PliqTypes.StakeStatus.Released;
        if (refund > 0) IERC20(s.token).safeTransfer(s.staker, refund);
        emit StakeReleased(stakeId, refund);
    }

    function getStakeById(uint256 id) external view returns (PliqTypes.StakeInfo memory) { return _stakes[id]; }
    function setMinimumStake(uint128 amount) external onlyRole(DEFAULT_ADMIN_ROLE) { minimumStake = amount; }
    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) { treasury = _treasury; }
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
