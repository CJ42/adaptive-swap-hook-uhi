// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IVolatilityDataOracle {
    function getLatestVolatilityData() external view returns (int256);
}
