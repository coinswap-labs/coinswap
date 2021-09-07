// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.6.12;

import './libraries/TransferHelper.sol';
import './libraries/CoinSwapV1Library.sol';
import './libraries/SafeMath.sol';
import './interfaces/IWETH.sol';
import "./interfaces/IOracle.sol";

interface ICoinSwapV1Factory1 {
    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface ISwapMining {
    function swap(address account, address input, address output, uint256 amount) external returns (bool);
}

contract CoinSwapV1Router02 {
    using SafeMath for uint;

    address public owner;
    address public immutable factory;//
    address public immutable WETH;
    address public swapMining;
    address public feeManager;
    IOracle public oracle;

    event FeeSplit(address src, uint256 _tokenId, address _token, address _to, uint256 _value);
    event FeeBurn(address _token, address _to, uint256 _value);

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'CoinSwapV1Router02: EXPIRED');
        _;
    }

    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
        owner = msg.sender;
    }

    receive() external payable {
        assert(msg.sender == WETH);
        // only accept ETH via fallback from the WETH contract
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "manger: caller is not the manger");
        _;
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function setSwapMining(address _swapMining) public onlyOwner {
        swapMining = _swapMining;
    }

    function setFeeManager(address _feeManager) public onlyOwner {
        feeManager = _feeManager;
    }

    function setOracle(IOracle _oracle) public onlyOwner {
        oracle = _oracle;
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (ICoinSwapV1Factory1(factory).getPair(tokenA, tokenB) == address(0)) {
            ICoinSwapV1Factory1(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = CoinSwapV1Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = CoinSwapV1Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'CoinSwapV1Router02: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = CoinSwapV1Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'CoinSwapV1Router02: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = CoinSwapV1Library.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = ICoinSwapV1Pair(pair).mint(to);
        updatePrice(tokenA, tokenB);
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = CoinSwapV1Library.pairFor(factory, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value : amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = ICoinSwapV1Pair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
        updatePrice(token, WETH);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = CoinSwapV1Library.pairFor(factory, tokenA, tokenB);
        ICoinSwapV1Pair(pair).transferFrom(msg.sender, pair, liquidity);
        // send liquidity to pair
        (uint amount0, uint amount1) = ICoinSwapV1Pair(pair).burn(to);
        (address token0,) = CoinSwapV1Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'CoinSwapV1Router02: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'CoinSwapV1Router02: INSUFFICIENT_B_AMOUNT');
        updatePrice(tokenA, tokenB);
    }

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
        updatePrice(token, WETH);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual returns (uint amountA, uint amountB) {
        address pair = CoinSwapV1Library.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(- 1) : liquidity;
        ICoinSwapV1Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
        updatePrice(tokenA, tokenB);
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual returns (uint amountToken, uint amountETH) {
        address pair = CoinSwapV1Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(- 1) : liquidity;
        ICoinSwapV1Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
        updatePrice(token, WETH);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
        updatePrice(token, WETH);
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual returns (uint amountETH) {
        address pair = CoinSwapV1Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(- 1) : liquidity;
        ICoinSwapV1Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
        updatePrice(token, WETH);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, uint[] memory feeAmounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = CoinSwapV1Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            bool can = false;
            if (CoinSwapV1Library.isSupportSwitch(feeManager, msg.sender) && feeAmounts[i] > 0) {
                feeTransFer(msg.sender, feeAmounts[i]);
                can = IFeeManager(feeManager).isOpenSwapMining() == 0;
            }
            if ((swapMining != address(0)) && !can) {
                ISwapMining(swapMining).swap(msg.sender, input, output, amountOut);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? CoinSwapV1Library.pairFor(factory, output, path[i + 2]) : _to;
            ICoinSwapV1Pair(CoinSwapV1Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0), msg.sender
            );
            updatePrice(path[i], path[i + 1]);
        }
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual ensure(deadline) returns (uint[] memory amounts) {
        require(feeManager != address(0), "ROUTER:feeManager is not zero address");
        uint[] memory feeAmounts;
        (amounts, feeAmounts) = CoinSwapV1Library.getAmountsOut1(factory, amountIn, path, feeManager, msg.sender);
        require(amounts[amounts.length - 1] >= amountOutMin, 'CoinSwapV1Router02: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CoinSwapV1Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, feeAmounts, path, to);
    }

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual ensure(deadline) returns (uint[] memory amounts) {
        require(feeManager != address(0), "ROUTER:feeManager is not zero address");
        uint[] memory feeAmounts;
        (amounts, feeAmounts) = CoinSwapV1Library.getAmountsIn1(factory, amountOut, path, feeManager, msg.sender);
        require(amounts[0] <= amountInMax, 'CoinSwapV1Router02: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CoinSwapV1Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, feeAmounts, path, to);
    }

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external virtual payable ensure(deadline) returns (uint[] memory amounts){
        require(path[0] == WETH, 'CoinSwapV1Router02: INVALID_PATH');
        require(feeManager != address(0), "ROUTER:feeManager is not zero address");
        uint[] memory feeAmounts;
        (amounts, feeAmounts) = CoinSwapV1Library.getAmountsOut1(factory, msg.value, path, feeManager, msg.sender);
        require(amounts[amounts.length - 1] >= amountOutMin, 'CoinSwapV1Router02: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value : amounts[0]}();
        assert(IWETH(WETH).transfer(CoinSwapV1Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, feeAmounts, path, to);
    }

    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline) external virtual ensure(deadline) returns (uint[] memory amounts){
        require(path[path.length - 1] == WETH, 'CoinSwapV1Router02: INVALID_PATH');
        require(feeManager != address(0), "ROUTER:feeManager is not zero address");
        uint[] memory feeAmounts;
        (amounts, feeAmounts) = CoinSwapV1Library.getAmountsIn1(factory, amountOut, path, feeManager, msg.sender);
        require(amounts[0] <= amountInMax, 'CoinSwapV1Router02: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CoinSwapV1Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, feeAmounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external virtual ensure(deadline) returns (uint[] memory amounts){
        require(path[path.length - 1] == WETH, 'CoinSwapV1Router02: INVALID_PATH');
        require(feeManager != address(0), "ROUTER:feeManager is not zero address");
        uint[] memory feeAmounts;
        (amounts, feeAmounts) = CoinSwapV1Library.getAmountsOut1(factory, amountIn, path, feeManager, msg.sender);
        require(amounts[amounts.length - 1] >= amountOutMin, 'CoinSwapV1Router02: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CoinSwapV1Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, feeAmounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline) external virtual payable ensure(deadline) returns (uint[] memory amounts){
        require(path[0] == WETH, 'CoinSwapV1Router02: INVALID_PATH');
        require(feeManager != address(0), "ROUTER:feeManager is not zero address");
        uint[] memory feeAmounts;
        (amounts, feeAmounts) = CoinSwapV1Library.getAmountsIn1(factory, amountOut, path, feeManager, msg.sender);
        require(amounts[0] <= msg.value, 'CoinSwapV1Router02: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value : amounts[0]}();
        assert(IWETH(WETH).transfer(CoinSwapV1Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, feeAmounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    struct Params {
        uint amountInput;
        uint amountOutput;
        uint feeAmount;
        uint reserve0;
        uint reserve1;
        uint reserveInput;
        uint reserveOutput;
    }
    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = CoinSwapV1Library.sortTokens(input, output);
            ICoinSwapV1Pair pair = ICoinSwapV1Pair(CoinSwapV1Library.pairFor(factory, input, output));
            Params memory params = Params(0, 0, 0, 0, 0, 0, 0);
            bool can = false;
            {// scope to avoid stack too deep errors
                (params.reserve0, params.reserve1,) = pair.getReserves();
                (params.reserveInput, params.reserveOutput) = input == token0 ? (params.reserve0, params.reserve1) : (params.reserve1, params.reserve0);
                params.amountInput = IERC20(input).balanceOf(address(pair)).sub(params.reserveInput);

                (params.amountOutput) = CoinSwapV1Library.getAmountOut(params.amountInput, params.reserveInput, params.reserveOutput);

                if (CoinSwapV1Library.isSupportSwitch(feeManager, msg.sender)) {
                    uint256 outValue;
                    (outValue, params.feeAmount) = CoinSwapV1Library.getAmountOutNoFee1(params.amountInput, params.reserveInput, params.reserveOutput, feeManager, path[i], path[i + 1]);
                    if (params.feeAmount > 0 && IERC20(IFeeManager(feeManager).feeToken()).balanceOf(msg.sender) >= params.feeAmount) {
                        params.amountOutput = outValue;
                        feeTransFer(msg.sender, params.feeAmount);
                        can = IFeeManager(feeManager).isOpenSwapMining() == 0;
                    }
                }
            }
            if ((swapMining != address(0)) && !can) {
                ISwapMining(swapMining).swap(msg.sender, input, output, params.amountOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), params.amountOutput) : (params.amountOutput, uint(0));
            address to = i < path.length - 2 ? CoinSwapV1Library.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0), msg.sender);
            updatePrice(path[i], path[i + 1]);
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CoinSwapV1Library.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'CoinSwapV1Router02: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual payable ensure(deadline) {
        require(path[0] == WETH, 'CoinSwapV1Router02: INVALID_PATH');
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value : amountIn}();
        assert(IWETH(WETH).transfer(CoinSwapV1Library.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'CoinSwapV1Router02: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual ensure(deadline) {
        require(path[path.length - 1] == WETH, 'CoinSwapV1Router02: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CoinSwapV1Library.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'CoinSwapV1Router02: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    function feeTransFer(address from, uint feeValue) internal {
        if (IFeeManager(feeManager).isBurn() == 1) {
            address burnAddress = IFeeManager(feeManager).blackHoleAddress();
            TransferHelper.safeTransferFrom(IFeeManager(feeManager).feeToken(), from, burnAddress, feeValue);
            emit FeeBurn(IFeeManager(feeManager).feeToken(), burnAddress, feeValue);
        } else {
            address feeAddress = IFeeManager(feeManager).defaultFeeAddress();
            TransferHelper.safeTransferFrom(IFeeManager(feeManager).feeToken(), from, feeAddress, feeValue);
            emit FeeSplit(from, 0, IFeeManager(feeManager).feeToken(), feeAddress, feeValue);
        }
    }

    function updatePrice(address tokenA, address tokenB) internal {
        if (address(oracle) != address(0)) {
            oracle.update(tokenA, tokenB);
        }
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual returns (uint amountB) {
        return CoinSwapV1Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure virtual returns (uint amountOut){
        (amountOut) = CoinSwapV1Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure virtual returns (uint amountIn){
        (amountIn) = CoinSwapV1Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path) public view virtual returns (uint[] memory amounts){
        (amounts,) = CoinSwapV1Library.getAmountsOut1(factory, amountIn, path, feeManager, msg.sender);
    }

    function getAmountsIn(uint amountOut, address[] memory path) public view virtual returns (uint[] memory amounts){
        (amounts,) = CoinSwapV1Library.getAmountsIn1(factory, amountOut, path, feeManager, msg.sender);
    }
}
