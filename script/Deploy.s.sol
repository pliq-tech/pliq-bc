// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/PliqRegistry.sol";
import "../src/RentalAgreement.sol";
import "../src/StakingManager.sol";
import "../src/ReputationAccumulator.sol";
import "../src/PaymentRouter.sol";
import "../src/DisputeResolver.sol";

contract DeployScript is Script {
    function run() external {
        address worldIdRouter = vm.envAddress("WORLD_ID_ROUTER_ADDRESS");
        string memory actionId = vm.envString("WORLD_ID_ACTION_ID");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address usdcToken = vm.envAddress("USDC_TOKEN_ADDRESS");

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        // 1. PliqRegistry (standalone, only needs World ID router)
        PliqRegistry registry = new PliqRegistry(worldIdRouter, actionId);
        console.log("PliqRegistry:", address(registry));

        // 2. StakingManager (needs registry + treasury)
        StakingManager staking = new StakingManager(address(registry), treasury);
        console.log("StakingManager:", address(staking));

        // 3. ReputationAccumulator (needs registry)
        ReputationAccumulator reputation = new ReputationAccumulator(address(registry));
        console.log("ReputationAccumulator:", address(reputation));

        // 4. PaymentRouter (needs fee recipient = treasury)
        PaymentRouter router = new PaymentRouter(treasury);
        console.log("PaymentRouter:", address(router));

        // 5. RentalAgreement (needs registry, payment router, staking manager)
        RentalAgreement agreement = new RentalAgreement(
            address(registry),
            address(router),
            address(staking)
        );
        console.log("RentalAgreement:", address(agreement));

        // 6. DisputeResolver (needs rental agreement, staking manager, reputation accumulator)
        DisputeResolver dispute = new DisputeResolver(
            address(agreement),
            address(staking),
            address(reputation)
        );
        console.log("DisputeResolver:", address(dispute));

        // Post-deploy: Grant roles
        bytes32 DISPUTE_RESOLVER_ROLE = keccak256("DISPUTE_RESOLVER_ROLE");
        // ORACLE_ROLE and KEEPER_ROLE can be granted post-deploy to specific addresses

        staking.grantRole(DISPUTE_RESOLVER_ROLE, address(dispute));
        console.log("Granted DISPUTE_RESOLVER_ROLE to DisputeResolver in StakingManager");

        agreement.grantRole(keccak256("DISPUTE_RESOLVER_ROLE"), address(dispute));
        console.log("Granted DISPUTE_RESOLVER_ROLE to DisputeResolver in RentalAgreement");

        // Configure supported tokens
        router.addSupportedToken(usdcToken);
        console.log("USDC added to PaymentRouter allowlist");

        // Set minimum stakes
        staking.setMinimumStake(PliqTypes.StakeType.Listing, 50e6);
        staking.setMinimumStake(PliqTypes.StakeType.Visit, 10e6);
        staking.setMinimumStake(PliqTypes.StakeType.Rent, 50e6);
        console.log("Minimum stakes configured");

        vm.stopBroadcast();

        // Log deployment summary
        console.log("--- Deployment Complete ---");
        console.log("Network: Base Sepolia / World Chain");
    }
}
