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

/// @title StakingManager - Protocol staking for listings, visits, and rentals with slashing
/// @notice Manages economic stakes with per-type minimums, slashing by authorized roles, and treasury routing
contract StakingManager is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant DISPUTE_RESOLVER_ROLE = keccak256("DISPUTE_RESOLVER_ROLE");

    IPliqRegistry public registry;
    address public treasury;

    mapping(uint256 => PliqTypes.Stake) private _stakes;
    mapping(uint256 => address) private _stakeTokens;
    mapping(PliqTypes.StakeType => uint128) private _minimumStakes;
    mapping(address => uint256[]) private _userStakes;
    uint256 public stakeCount;

    event StakeCreated(uint256 indexed stakeId, address indexed staker, PliqTypes.StakeType stakeType, uint128 amount);
    event StakeReleased(uint256 indexed stakeId, address indexed staker, uint128 amount);
    event StakeSlashed(uint256 indexed stakeId, address indexed staker, uint128 amount, string reason);

    constructor(address _registry, address _treasury) {
        if (_registry == address(0) || _treasury == address(0)) revert PliqErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        registry = IPliqRegistry(_registry);
        treasury = _treasury;

        _minimumStakes[PliqTypes.StakeType.Listing] = 50e6;
        _minimumStakes[PliqTypes.StakeType.Visit] = 10e6;
        _minimumStakes[PliqTypes.StakeType.Rent] = 50e6;
    }

    function _stake(PliqTypes.StakeType stakeType, uint256 referenceId, uint128 amount, address token) internal returns (uint256) {
        if (amount == 0) revert PliqErrors.ZeroAmount();
        if (!registry.isRegistered(msg.sender)) revert PliqErrors.NotRegistered(msg.sender);
        uint128 minimum = _minimumStakes[stakeType];
        if (amount < minimum) revert PliqErrors.InsufficientStakeAmount(amount, minimum);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        stakeCount++;
        _stakes[stakeCount] = PliqTypes.Stake({
            staker: msg.sender,
            stakeType: stakeType,
            amount: amount,
            referenceId: referenceId,
            status: PliqTypes.StakeStatus.Active,
            createdAt: uint64(block.timestamp)
        });
        _stakeTokens[stakeCount] = token;
        _userStakes[msg.sender].push(stakeCount);

        emit StakeCreated(stakeCount, msg.sender, stakeType, amount);
        return stakeCount;
    }

    function stakeToList(uint256 listingId, uint128 amount, address token) external nonReentrant whenNotPaused returns (uint256) {
        return _stake(PliqTypes.StakeType.Listing, listingId, amount, token);
    }

    function stakeToVisit(uint256 listingId, uint128 amount, address token) external nonReentrant whenNotPaused returns (uint256) {
        return _stake(PliqTypes.StakeType.Visit, listingId, amount, token);
    }

    function stakeToRent(uint256 agreementId, uint128 amount, address token) external nonReentrant whenNotPaused returns (uint256) {
        return _stake(PliqTypes.StakeType.Rent, agreementId, amount, token);
    }

    /// @notice Slash a stake (DISPUTE_RESOLVER_ROLE or OPERATOR_ROLE)
    function slash(uint256 stakeId, uint128 amount, string calldata reason) external nonReentrant {
        if (!hasRole(DISPUTE_RESOLVER_ROLE, msg.sender) && !hasRole(OPERATOR_ROLE, msg.sender)) {
            revert PliqErrors.Unauthorized(msg.sender);
        }

        PliqTypes.Stake storage s = _stakes[stakeId];
        if (s.status != PliqTypes.StakeStatus.Active && s.status != PliqTypes.StakeStatus.PartiallySlashed) {
            revert PliqErrors.StakeNotActive(stakeId);
        }
        if (amount > s.amount) revert PliqErrors.SlashExceedsStake(amount, s.amount);

        s.amount -= amount;
        s.status = s.amount == 0 ? PliqTypes.StakeStatus.Slashed : PliqTypes.StakeStatus.PartiallySlashed;

        IERC20(_stakeTokens[stakeId]).safeTransfer(treasury, amount);
        emit StakeSlashed(stakeId, s.staker, amount, reason);
    }

    /// @notice Release remaining stake back to staker
    function releaseStake(uint256 stakeId) external nonReentrant {
        PliqTypes.Stake storage s = _stakes[stakeId];
        if (s.createdAt == 0) revert PliqErrors.StakeNotFound(stakeId);
        if (s.status == PliqTypes.StakeStatus.Released) revert PliqErrors.StakeAlreadyReleased(stakeId);
        if (msg.sender != s.staker && !hasRole(OPERATOR_ROLE, msg.sender)) {
            revert PliqErrors.Unauthorized(msg.sender);
        }

        uint128 refund = s.amount;
        s.amount = 0;
        s.status = PliqTypes.StakeStatus.Released;

        if (refund > 0) {
            IERC20(_stakeTokens[stakeId]).safeTransfer(s.staker, refund);
        }
        emit StakeReleased(stakeId, s.staker, refund);
    }

    // View functions
    function getStakeById(uint256 id) external view returns (PliqTypes.Stake memory) { return _stakes[id]; }
    function getStakesByUser(address user) external view returns (uint256[] memory) { return _userStakes[user]; }
    function getMinimumStake(PliqTypes.StakeType stakeType) external view returns (uint128) { return _minimumStakes[stakeType]; }

    // Admin functions
    function setMinimumStake(PliqTypes.StakeType stakeType, uint128 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _minimumStakes[stakeType] = amount;
    }

    function setTreasuryAddress(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_treasury == address(0)) revert PliqErrors.ZeroAddress();
        treasury = _treasury;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
