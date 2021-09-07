// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "./interfaces/ICoinSwapV1Pair.sol";
import "./libraries/CoinSwapV1Library.sol";
import "./libraries/SafeMath.sol";
import "./interfaces/ICoinSwapV1Factory.sol";

library FixedPoint {
    struct uq112x112 {
        uint224 _x;
    }

    // range: [0, 2**144 - 1]
    // resolution: 1 / 2**112
    struct uq144x112 {
        uint _x;
    }

    uint8 private constant RESOLUTION = 112;

    // encode a uint112 as a UQ112x112
    function encode(uint112 x) internal pure returns (uq112x112 memory) {
        return uq112x112(uint224(x) << RESOLUTION);
    }

    // encodes a uint144 as a UQ144x112
    function encode144(uint144 x) internal pure returns (uq144x112 memory) {
        return uq144x112(uint256(x) << RESOLUTION);
    }

    // divide a UQ112x112 by a uint112, returning a UQ112x112
    function div(uq112x112 memory self, uint112 x) internal pure returns (uq112x112 memory) {
        require(x != 0, 'FixedPoint: DIV_BY_ZERO');
        return uq112x112(self._x / uint224(x));
    }

    // multiply a UQ112x112 by a uint, returning a UQ144x112
    // reverts on overflow
    function mul(uq112x112 memory self, uint y) internal pure returns (uq144x112 memory) {
        uint z;
        require(y == 0 || (z = uint(self._x) * y) / y == uint(self._x), "FixedPoint: MULTIPLICATION_OVERFLOW");
        return uq144x112(z);
    }

    // returns a UQ112x112 which represents the ratio of the numerator to the denominator
    // equivalent to encode(numerator).div(denominator)
    function fraction(uint112 numerator, uint112 denominator) internal pure returns (uq112x112 memory) {
        require(denominator > 0, "FixedPoint: DIV_BY_ZERO");
        return uq112x112((uint224(numerator) << RESOLUTION) / denominator);
    }

    // decode a UQ112x112 into a uint112 by truncating after the radix point
    function decode(uq112x112 memory self) internal pure returns (uint112) {
        return uint112(self._x >> RESOLUTION);
    }

    // decode a UQ144x112 into a uint144 by truncating after the radix point
    function decode144(uq144x112 memory self) internal pure returns (uint144) {
        return uint144(self._x >> RESOLUTION);
    }
}

library CoinSwapOracleLibrary {
    using FixedPoint for *;

    // helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**32 - 1]
    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    function currentCumulativePrices(
        address pair
    ) internal view returns (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) {
        blockTimestamp = currentBlockTimestamp();
        price0Cumulative = ICoinSwapV1Pair(pair).price0CumulativeLast();
        price1Cumulative = ICoinSwapV1Pair(pair).price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = ICoinSwapV1Pair(pair).getReserves();
        if (blockTimestampLast != blockTimestamp) {
            // subtraction overflow is desired
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            price0Cumulative += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
            price1Cumulative += uint(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
        }
    }
}

contract Oracle {
    using FixedPoint for *;
    using SafeMath for uint;

    struct Observation {
        uint timestamp;
        uint price0Cumulative;
        uint price1Cumulative;
    }

    address public immutable factory;
    address public coins;
    address public usdt;
    uint public constant CYCLE = 30 minutes;
    Observation[144]  public  observations;
    uint public nextUpdateIndex;

    // mapping from pair address to a list of price observations of that pair
    mapping(address => Observation) public pairObservations;

    constructor(address factory_, address coins_, address usdt_) public {
        factory = factory_;
        coins = coins_;
        usdt = usdt_;
    }

    function update(address tokenA, address tokenB) external {
        address pair = ICoinSwapV1Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "Oracle：pair is not create");
        Observation storage observation = pairObservations[pair];
        uint timeElapsed = block.timestamp - observation.timestamp;
        if (timeElapsed >= CYCLE) {
            (uint price0Cumulative, uint price1Cumulative,) = CoinSwapOracleLibrary.currentCumulativePrices(pair);
            if (price0Cumulative != 0 && price1Cumulative != 0) {
                observation.timestamp = block.timestamp;
                observation.price0Cumulative = price0Cumulative;
                observation.price1Cumulative = price1Cumulative;
                if (ICoinSwapV1Factory(factory).getPair(coins, usdt) == pair) {
                    observations[nextUpdateIndex].timestamp = block.timestamp;
                    observations[nextUpdateIndex].price0Cumulative = price0Cumulative;
                    observations[nextUpdateIndex].price1Cumulative = price1Cumulative;
                    nextUpdateIndex++;
                    if (nextUpdateIndex > 143) {
                        nextUpdateIndex = 0;
                    }
                }
            }
        }
    }

    function consultPriceDecPercent() external view returns (uint){
        address pair = ICoinSwapV1Factory(factory).getPair(coins, usdt);
        Observation storage observation = pairObservations[pair];
        uint timeElapsed = block.timestamp - observation.timestamp;
        if (timeElapsed > 0) {
            (uint price0Cumulative, uint price1Cumulative,) = CoinSwapOracleLibrary.currentCumulativePrices(pair);
            uint priceAverage1;
            uint priceAverage2;
            Observation memory priceObservation;
            if (observations[143].timestamp > 0) {
                priceObservation = observations[nextUpdateIndex];
            } else {
                priceObservation = observations[0];
            }
            uint timeElapsed1 = block.timestamp - priceObservation.timestamp;

            if (coins < usdt) {
                priceAverage1 = price0Cumulative .sub(observation.price0Cumulative)  .div(timeElapsed);
                priceAverage2 = price0Cumulative .sub(priceObservation.price0Cumulative) .div(timeElapsed1);
            } else {
                priceAverage1 = price1Cumulative .sub(observation.price1Cumulative) .div(timeElapsed);
                priceAverage2 = price1Cumulative .sub(priceObservation.price1Cumulative) .div(timeElapsed1);
            }
            uint256 rate;
            if (priceAverage1 >= priceAverage2) {
                rate = priceAverage1.sub(priceAverage2).mul(10000).div(priceAverage2);
            } else {
                rate = priceAverage2.sub(priceAverage1).mul(10000).div(priceAverage2);
            }
            return rate > 9000 ? 9000 : rate;
        }
        return 0;
    }

    function computeAmountOut(
        uint priceCumulativeStart, uint priceCumulativeEnd,
        uint timeElapsed, uint amountIn
    ) private pure returns (uint amountOut) {
        // overflow is desired.
        FixedPoint.uq112x112 memory priceAverage = FixedPoint.uq112x112(
            uint224((priceCumulativeEnd - priceCumulativeStart) / timeElapsed)
        );
        amountOut = priceAverage.mul(amountIn).decode144();
    }

    function consult(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut) {
        address pair = ICoinSwapV1Factory(factory).getPair(tokenIn, tokenOut);
        Observation storage observation = pairObservations[pair];
        uint timeElapsed = block.timestamp - observation.timestamp;
        (uint price0Cumulative, uint price1Cumulative,) = CoinSwapOracleLibrary.currentCumulativePrices(pair);
        (address token0,) = CoinSwapV1Library.sortTokens(tokenIn, tokenOut);

        if (token0 == tokenIn) {
            return computeAmountOut(observation.price0Cumulative, price0Cumulative, timeElapsed, amountIn);
        } else {
            return computeAmountOut(observation.price1Cumulative, price1Cumulative, timeElapsed, amountIn);
        }
    }
}
