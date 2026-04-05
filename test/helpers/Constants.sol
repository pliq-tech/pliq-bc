// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Constants {
    // Test addresses
    address constant ADMIN = address(0x1);
    address constant LANDLORD = address(0x2);
    address constant TENANT = address(0x3);
    address constant TREASURY = address(0x4);
    address constant ORACLE = address(0x5);
    address constant KEEPER = address(0x6);
    address constant JUROR_1 = address(0x7);
    address constant JUROR_2 = address(0x8);
    address constant JUROR_3 = address(0x9);
    address constant RANDOM_USER = address(0xA);

    // Test nullifier hashes
    uint256 constant NULLIFIER_1 = 12345678901234567890;
    uint256 constant NULLIFIER_2 = 98765432109876543210;
    uint256 constant NULLIFIER_3 = 11111111111111111111;

    // Test listing data
    bytes32 constant LISTING_HASH = keccak256("listing-1-ipfs-hash");
    bytes32 constant LEASE_HASH = keccak256("lease-agreement-hash");
    bytes32 constant CONDITION_REPORT_HASH = keccak256("condition-report");
    bytes32 constant CHECKOUT_REPORT_HASH = keccak256("checkout-report");
    bytes32 constant EVIDENCE_HASH = keccak256("evidence-hash");

    string constant METADATA_URI = "ipfs://QmTestHash";
    string constant EVIDENCE_URI = "ipfs://QmEvidenceHash";

    // Financial constants (6 decimals like USDC)
    uint128 constant DEPOSIT_AMOUNT = 2400e6; // 2400 USDC
    uint128 constant MONTHLY_RENT = 1200e6; // 1200 USDC
    uint128 constant MINIMUM_STAKE = 50e6; // 50 USDC
    uint128 constant STAKE_AMOUNT = 100e6; // 100 USDC

    // Time constants
    uint64 constant ONE_DAY = 1 days;
    uint64 constant ONE_MONTH = 30 days;

    // World ID
    uint256 constant ROOT = 1;
    string constant ACTION_ID = "pliq-register";
}
