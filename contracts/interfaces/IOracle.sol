// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.6.12;

interface IOracle {
    function update(address tokenA, address tokenB) external;

    function consult(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut);

    function consultPriceDecPercent() external view returns (uint);
}
