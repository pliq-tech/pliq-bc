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

        // 1. PliqRegistry
        PliqRegistry registry = new PliqRegistry(worldIdRouter, actionId);
        console.log("PliqRegistry:", address(registry));

        // 2. RentalAgreement
        RentalAgreement agreement = new RentalAgreement();
        console.log("RentalAgreement:", address(agreement));

        // 3. StakingManager
        StakingManager staking = new StakingManager(treasury);
        console.log("StakingManager:", address(staking));

        // 4. ReputationAccumulator
        ReputationAccumulator reputation = new ReputationAccumulator();
        console.log("ReputationAccumulator:", address(reputation));

        // 5. PaymentRouter
        PaymentRouter router = new PaymentRouter(treasury);
        console.log("PaymentRouter:", address(router));

        // 6. DisputeResolver
        DisputeResolver dispute = new DisputeResolver();
        console.log("DisputeResolver:", address(dispute));

        // Configure: add USDC as supported token
        router.setSupportedToken(usdcToken, true);
        console.log("USDC added to PaymentRouter allowlist");

        vm.stopBroadcast();
    }
}
