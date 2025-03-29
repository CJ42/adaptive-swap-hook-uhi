// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// modules
import {ECDSAServiceManagerBase} from "@eigenlayer-middleware/src/unaudited/ECDSAServiceManagerBase.sol";
import {MockServiceManagerImplementation} from "./MockServiceManagerImplementation.sol";

// interfaces
import {IServiceManager} from "@eigenlayer-middleware/src/interfaces/IServiceManager.sol";

/**
 * @title Primary entrypoint for providing market volatility data to smart contracts (e.g: Adaptive Swap).
 * @author CJ42
 */
contract VolatilityDataServiceManager is
    ECDSAServiceManagerBase,
    MockServiceManagerImplementation
{
    int256 internal _latestVolatility;

    uint256 public latestVolatilitySubmissionNumber;

    constructor(
        address _avsDirectory,
        address _stakeRegistry,
        address _rewardsCoordinator,
        address _delegationManager,
        address _allocationManager
    )
        ECDSAServiceManagerBase(
            _avsDirectory,
            _stakeRegistry,
            _rewardsCoordinator,
            _delegationManager,
            _allocationManager
        )
    {}

    function initialize(
        address initialOwner_,
        address rewardsInitiator_
    ) external initializer {
        __ServiceManagerBase_init(initialOwner_, rewardsInitiator_);
    }

    /// @dev This is submitted by the AVS operator
    function submitNewVolatilityData(int256 volatility) external {
        _latestVolatility = volatility;
        latestVolatilitySubmissionNumber++;
    }

    /// @dev This is consumed by the Uniswap v4 Hook contract
    function getLatestVolatilityData() external view returns (int256) {
        return _latestVolatility;
    }
}
