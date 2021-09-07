// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/ICoinSwapV1Router02.sol";
import "./interfaces/ICoinSwapV1Factory.sol";
import "./interfaces/ICoinSwapV1Pair.sol";
import "./libraries/TransferHelper.sol";

contract Migrator {
    using SafeMath for uint256;

    ICoinSwapV1Router02 public oldRouter;
    ICoinSwapV1Router02 public newRouter;

    ICoinSwapV1Factory public oldFactory;
    ICoinSwapV1Factory public newFactory;

    event Migrate (
        address user,
        address tokenA,
        address tokenB,
        uint256 liquidity
    );

    constructor(ICoinSwapV1Router02 _oldRouter, ICoinSwapV1Router02 _newRouter, ICoinSwapV1Factory _oldFactory, ICoinSwapV1Factory _newFactory) public {
        oldRouter = _oldRouter;
        newRouter = _newRouter;

        oldFactory = _oldFactory;
        newFactory = _newFactory;
    }

    function migrate(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline
    ) public {
        require(deadline >= block.timestamp, 'Migrate: EXPIRED');
        require(tokenA != tokenB, "Migrate: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Migrate: ZERO_ADDRESS');

        (uint256 amount0Min, uint256 amount1Min) = tokenA == token0 ? (amountAMin, amountBMin) : (amountBMin, amountAMin);

        (uint256 amount0, uint256 amount1) = removeLiquidity(token0, token1, liquidity, amount0Min, amount1Min);

        (uint256 pooledAmount0, uint256 pooledAmount1) = addLiquidity(token0, token1, amount0, amount1);


        if (amount0 > pooledAmount0) {
            TransferHelper.safeTransfer(token0, msg.sender, amount0 - pooledAmount0);
        }
        if (amount1 > pooledAmount1) {
            TransferHelper.safeTransfer(token1, msg.sender, amount1 - pooledAmount1);
        }
        emit Migrate(msg.sender, tokenA, tokenB, liquidity);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {

        address pairAddress = oldFactory.getPair(tokenA, tokenB);
        require(pairAddress != address(0), "Migrate: PAIR_NOT_EXIST");

        ICoinSwapV1Pair pair = ICoinSwapV1Pair(pairAddress);

        TransferHelper.safeTransferFrom(pairAddress, msg.sender, pairAddress, liquidity);

        (amountA, amountB) = pair.burn(address(this));

        require(amountA >= amountAMin, 'Migrate: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'Migrate: INSUFFICIENT_B_AMOUNT');
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired
    ) internal returns (uint256 amountA, uint256 amountB) {
        (address pairAddress, uint256 _amountA, uint256 _amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired);
        amountA = _amountA;
        amountB = _amountB;
        TransferHelper.safeTransfer(tokenA, pairAddress, amountA);
        TransferHelper.safeTransfer(tokenB, pairAddress, amountB);
        ICoinSwapV1Pair(pairAddress).mint(msg.sender);
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired
    ) internal returns (address pairAddress, uint256 amountA, uint256 amountB) {
        pairAddress = newFactory.getPair(tokenA, tokenB);
        if (pairAddress == address(0)) {
            pairAddress = newFactory.createPair(tokenA, tokenB);
        }
        ICoinSwapV1Pair pair = ICoinSwapV1Pair(pairAddress);
        (uint reserveA, uint reserveB,) = pair.getReserves();
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = amountADesired.mul(reserveB).div(reserveA);
            if (amountBOptimal <= amountBDesired) {
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = amountBDesired.mul(reserveA).div(reserveB);
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
}
