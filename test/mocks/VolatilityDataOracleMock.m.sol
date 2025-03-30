// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IVolatilityDataOracle} from "../../src/interfaces/IVolatilityDataOracle.sol";

contract VolatilityDataOracleMock is IVolatilityDataOracle {
    int256 private _volatility;

    function getLatestVolatilityData() external view override returns (int256) {
        return _volatility;
    }

    function setRegularVolatility() external {
        _volatility = 100; // 1%
    }

    function setHighVolatility() external {
        _volatility = 125 + 5; // 1.30%
    }

    function setLowVolatility() external {
        _volatility = 75 - 5; // 0.70%
    }
}
