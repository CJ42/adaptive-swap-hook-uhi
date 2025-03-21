// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IVolatilityOracle} from "../../src/interfaces/IVolatilityOracle.sol";

contract VolatilityOracleMock is IVolatilityOracle {
    uint256 private _volatility;

    function getVolatility() external view override returns (uint256) {
        return _volatility;
    }

    function setRegularVolatility() external {
        _volatility = 80_000; // 8%
    }

    function setHighVolatility() external {
        _volatility = 220_000; // 22%
    }

    function setLowVolatility() external {
        _volatility = 30_000; // 3%
    }
}
