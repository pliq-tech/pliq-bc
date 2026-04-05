// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/PliqTypes.sol";

interface IStakingManager {
    // Write
    function stakeToList(uint256 listingId, uint128 amount, address token) external returns (uint256 stakeId);
    function stakeToVisit(uint256 listingId, uint128 amount, address token) external returns (uint256 stakeId);
    function stakeToRent(uint256 agreementId, uint128 amount, address token) external returns (uint256 stakeId);
    function slash(uint256 stakeId, uint128 amount, string calldata reason) external;
    function releaseStake(uint256 stakeId) external;

    // Admin
    function setMinimumStake(PliqTypes.StakeType stakeType, uint128 amount) external;
    function setTreasuryAddress(address treasury) external;

    // Read
    function getStakeById(uint256 stakeId) external view returns (PliqTypes.Stake memory);
    function getStakesByUser(address user) external view returns (uint256[] memory);
    function getMinimumStake(PliqTypes.StakeType stakeType) external view returns (uint128);

    // Events
    event StakeCreated(uint256 indexed stakeId, address indexed staker, PliqTypes.StakeType stakeType, uint128 amount);
    event StakeReleased(uint256 indexed stakeId, address indexed staker, uint128 amount);
    event StakeSlashed(uint256 indexed stakeId, address indexed staker, uint128 amount, string reason);
}
