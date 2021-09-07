// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.6.12;

import '../interfaces/ICoinSwapV1Pair.sol';
import '../interfaces/IFeeManager.sol';
import "./SafeMath.sol";
import '../interfaces/IERC20.sol';

library CoinSwapV1Library {
    using SafeMath for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'CoinSwapV1Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'CoinSwapV1Library: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'84d36a1b225daa09c8a08b1b81c64849c8cb0cc8249e8ed1a4269841077e7d43' // init code hash
            ))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = ICoinSwapV1Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'CoinSwapV1Library: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'CoinSwapV1Library: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'CoinSwapV1Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'CoinSwapV1Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOutNoFee1(uint amountIn, uint reserveIn, uint reserveOut, address feeManager, address inToken, address outToken) internal view returns (uint amountOut, uint fee) {
        require(amountIn > 0, 'CoinSwapV1Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'CoinSwapV1Library: INSUFFICIENT_LIQUIDITY');
        uint realAmountIn = amountIn.mul(1000) / 997;
        fee = realAmountIn .sub(amountIn);
        uint numerator = amountIn.mul(reserveOut);
        uint denominator = reserveIn.add(amountIn);
        amountOut = numerator / denominator;
        fee = IFeeManager(feeManager).getTokenQuantity(inToken, outToken, fee);
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'CoinSwapV1Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'CoinSwapV1Library: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountInNoFee1(uint amountOut, uint reserveIn, uint reserveOut, address feeManager, address inToken, address outToken) internal view returns (uint amountIn, uint fee) {
        require(amountOut > 0, 'CoinSwapV1Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'CoinSwapV1Library: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        uint realAmountIn = (numerator / denominator).add(1);
        fee = realAmountIn.mul(3) / 1000;
        amountIn = realAmountIn.sub(fee);
        fee = IFeeManager(feeManager).getTokenQuantity(inToken, outToken, fee);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut1(address factory, uint amountIn, address[] memory path, address feeManager, address from) internal view returns (uint[] memory amounts, uint[] memory feeAmounts) {
        require(path.length >= 2, 'CoinSwapV1Library: INVALID_PATH');
        amounts = new uint[](path.length);
        feeAmounts = new uint[](path.length);
        amounts[0] = amountIn;
        uint needCoinsNum;
        for (uint i; i < path.length - 1; i++) {
            (amounts[i + 1], feeAmounts[i], needCoinsNum) = feeConsult(factory, amounts[i], feeManager, path[i], path[i + 1], false, from, needCoinsNum, i);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn1(address factory, uint amountOut, address[] memory path, address feeManager, address from) internal view returns (uint[] memory amounts, uint[] memory feeAmounts) {
        require(path.length >= 2, 'CoinSwapV1Library: INVALID_PATH');
        amounts = new uint[](path.length);
        feeAmounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        uint needCoinsNum;
        for (uint i = path.length - 1; i > 0; i--) {
            (amounts[i - 1], feeAmounts[i - 1], needCoinsNum) = feeConsult(factory, amounts[i], feeManager, path[i - 1], path[i], true, from, needCoinsNum, i);
        }
    }

    function isSupportSwitch(address feeManager, address from) internal view returns (bool){
        return IFeeManager(feeManager).supportDeductionFeeSwitches(from) == 1;
    }

    struct Params {
        uint amount;
        uint fee;
        uint tempNum;
        uint reserveIn;
        uint reserveOut;
        uint newNeedCoinsNum;
    }

    function feeConsult(address factory, uint amountInput, address feeManager, address path, address path1, bool isIn, address from, uint needCoinsNum, uint i) internal view returns (uint, uint, uint){
        Params memory params = Params(0, 0, 0, 0, 0, 0);
        (params.reserveIn, params.reserveOut) = getReserves(factory, path, path1);
        if (isSupportSwitch(feeManager, from)) {
            if (isIn) {
                (params.amount, params.fee) = getAmountInNoFee1(amountInput, params.reserveIn, params.reserveOut, feeManager, path, path1);
                if (i == 1) params.tempNum = params.tempNum.add(params.amount);
            } else {
                (params.amount, params.fee) = getAmountOutNoFee1(amountInput, params.reserveIn, params.reserveOut, feeManager, path, path1);
                if (i == 0) params.tempNum = params.tempNum.add(amountInput);
            }
            if (path != IFeeManager(feeManager).feeToken()) {
                params.tempNum = 0;
            }
            params.newNeedCoinsNum = params.tempNum.add(needCoinsNum).add(params.fee);
            if (params.fee > 0 && IERC20(IFeeManager(feeManager).feeToken()).balanceOf(from) >= params.newNeedCoinsNum) {
                return (params.amount, params.fee, params.newNeedCoinsNum);
            }
        }
        params.fee = 0;
        params.tempNum = 0;
        if (isIn) {
            (params.amount) = getAmountIn(amountInput, params.reserveIn, params.reserveOut);
            if (i == 1) params.tempNum = params.tempNum.add(params.amount);
        } else {
            (params.amount) = getAmountOut(amountInput, params.reserveIn, params.reserveOut);
            if (i == 0) params.tempNum = params.tempNum.add(amountInput);
        }
        if (path != IFeeManager(feeManager).feeToken()) {
            params.tempNum = 0;
        }
        return (params.amount, params.fee, params.tempNum.add(needCoinsNum));
    }
}
