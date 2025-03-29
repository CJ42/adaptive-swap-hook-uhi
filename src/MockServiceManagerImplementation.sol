// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// modules
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

// interfaces
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";

import {IServiceManager} from "@eigenlayer-middleware/src/interfaces/IServiceManager.sol";

/// @dev This is a mock implementation of the IServiceManager interface that does not implement anything
/// in the functions. It was created to keep the code of the `VolatilityDataServiceManager` minimal.
abstract contract MockServiceManagerImplementation is
    IServiceManager,
    OwnableUpgradeable
{
    /// @dev This function is commented out as it is derived by the ECDSA Service Manager
    // function createAVSRewardsSubmission(
    //     IRewardsCoordinator.RewardsSubmission[] calldata rewardsSubmissions
    // ) external {}

    function addPendingAdmin(address admin) external onlyOwner {}

    function removePendingAdmin(address pendingAdmin) external onlyOwner {}

    function removeAdmin(address admin) external onlyOwner {}

    function setAppointee(
        address appointee,
        address target,
        bytes4 selector
    ) external onlyOwner {}

    function removeAppointee(
        address appointee,
        address target,
        bytes4 selector
    ) external onlyOwner {}

    function deregisterOperatorFromOperatorSets(
        address operator,
        uint32[] memory operatorSetIds
    ) external {
        // unused
    }
}
