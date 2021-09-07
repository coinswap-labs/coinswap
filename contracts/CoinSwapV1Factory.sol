// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import './interfaces/ICoinSwapV1Factory.sol';
import './CoinSwapV1Pair.sol';

contract CoinSwapV1Factory {
    address public feeTo;
    address public feeManager;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);
    event SetFeeTo(address _feeTo);
    event SetFeeManager(address _feeManager);
    event SetFeeToSetter(address _feeToSetter);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'CoinSwapV1: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'CoinSwapV1: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'CoinSwapV1: PAIR_EXISTS');
        // single check is sufficient
        bytes memory bytecode = type(CoinSwapV1Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        CoinSwapV1Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'CoinSwapV1: FORBIDDEN');
        feeTo = _feeTo;
        emit SetFeeTo(_feeTo);
    }

    function setFeeManager(address _feeManager) external {
        require(msg.sender == feeToSetter, 'CoinSwapV1: feeManager');
        feeManager = _feeManager;
        emit SetFeeManager(_feeManager);
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'CoinSwapV1: FORBIDDEN');
        feeToSetter = _feeToSetter;
        emit SetFeeToSetter(_feeToSetter);
    }

    function getPairInitCode() external pure returns (bytes32){
        return keccak256(abi.encodePacked(type(CoinSwapV1Pair).creationCode));
    }
}
