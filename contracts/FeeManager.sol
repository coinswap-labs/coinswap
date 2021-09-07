// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "./libraries/SafeMath.sol";
import "./interfaces/IInviteManager.sol";
import './libraries/CoinSwapV1Library.sol';
import "./interfaces/ICoinSwapV1Factory.sol";

contract FeeManager is Ownable {
    using SafeMath for uint;
    address public defaultFeeAddress;
    address public blackHoleAddress;
    address public router;
    address public feeToken;
    address public factory;
    uint8 public isBurn = 0;
    uint8 public isOpenSwapMining = 1;
    address public inviteManger;

    //1 is support ,0 no
    mapping(address => uint8) public supportDeductionFeeSwitches;
    //value is  5000/10000
    uint256 public supportDeductionFeeValue = 6000;

    uint256 public feeToRate = 5;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _feeWhitelist;

    constructor(address _feeToken, address _feeAddress) public {
        feeToken = _feeToken;
        defaultFeeAddress = _feeAddress;
        blackHoleAddress = address(1);
    }

    function setDefaultFeeAddress(address _feeAddress) external onlyOwner {
        require(_feeAddress != address(0), "_feeAddress is not zero address");
        defaultFeeAddress = _feeAddress;
    }

    function setBlackHoleAddress(address _blackHoleAddress) external onlyOwner {
        blackHoleAddress = _blackHoleAddress;
    }

    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "router is not zero address");
        router = _router;
    }

    function setInviteManager(address _inviteManger) external onlyOwner {
        require(_inviteManger != address(0), "_subManager is not zero address");
        inviteManger = _inviteManger;
    }

    function setFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "_factory is zero address");
        factory = _factory;
    }

    function setBurnSwitch(uint8 _isBurn) external onlyOwner {
        require(_isBurn == 0 || _isBurn == 1, "_isBurn is error");
        isBurn = _isBurn;
    }

    function setOpenSwapMiningSwitch(uint8 _isOpenSwapMining) external onlyOwner {
        require(_isOpenSwapMining == 0 || _isOpenSwapMining == 1, "_isOpenSwapMining is error");
        isOpenSwapMining = _isOpenSwapMining;
    }

    function setSupportDeductionFeeSwitch(uint8 _isSupport) external {
        require(_isSupport >= 0, "_isSupport value error");
        supportDeductionFeeSwitches[msg.sender] = _isSupport;
    }

    function setSupportDeductionFeeValue(uint256 _n) external onlyOwner {
        require(_n > 0 && _n <= 10000, "_n value error");
        supportDeductionFeeValue = _n;
    }

    // _feeToRate 1 is  3/6 ,2 is 2/6 ,5 is 1/6 ,0 is 6/6
    function setFeeToRateValue(uint256 _feeToRate) external onlyOwner {
        require(_feeToRate == 0 || _feeToRate == 1 || _feeToRate == 2 || _feeToRate == 5, "_feeToRate value error");
        feeToRate = _feeToRate;
    }

    struct Params1 {
        uint256 _rootId;
        address _rootOwner;
        uint256 _rootRate;
        uint256 _parentId;
        address _parentOwner;
        uint256 _parentRate;
    }

    function feeSplit(address from, uint256 feeValue) external view returns (uint[] memory valueData, address[] memory addressData) {
        require(inviteManger != address(0), "inviteManger is zero address");
        require(from != address(0), "from is zero address");
        Params1 memory params = Params1(0, address(0), 0, 0, address(0), 0);
        (params._rootId, params._rootOwner, params._rootRate, params._parentId, params._parentOwner, params._parentRate) = IInviteManager(inviteManger).swapKickback(from);
        valueData = new uint[](4);
        addressData = new address[](2);

        bool isRootHave = params._rootOwner != address(0) && params._rootId > 0 && params._rootRate > 0;
        bool isParentHave = params._parentOwner != address(0) && params._parentId > 0 && params._parentRate > 0;
        uint rootFeeValue;
        uint parentFeeValue;

        if (isParentHave && isRootHave) {
            parentFeeValue = feeValue.mul(params._parentRate).div(10 ** IInviteManager(inviteManger).kickbackDecimals());
            rootFeeValue = feeValue.mul(params._rootRate).div(10 ** IInviteManager(inviteManger).kickbackDecimals()).sub(parentFeeValue);

            valueData[0] = rootFeeValue;
            valueData[1] = parentFeeValue;
            valueData[2] = params._rootId;
            valueData[3] = params._parentId;

            addressData[0] = params._rootOwner;
            addressData[1] = params._parentOwner;
        } else if (isParentHave && !isRootHave) {
            parentFeeValue = feeValue.mul(params._parentRate).div(10 ** IInviteManager(inviteManger).kickbackDecimals());

            valueData[0] = 0;
            valueData[1] = parentFeeValue;
            valueData[2] = params._rootId;
            valueData[3] = params._parentId;

            addressData[0] = params._rootOwner;
            addressData[1] = params._parentOwner;
        } else if (!isParentHave && isRootHave) {
            rootFeeValue = feeValue.mul(params._rootRate).div(10 ** IInviteManager(inviteManger).kickbackDecimals());

            valueData[0] = rootFeeValue;
            valueData[1] = 0;
            valueData[2] = params._rootId;
            valueData[3] = params._parentId;

            addressData[0] = params._rootOwner;
            addressData[1] = params._parentOwner;
        } else {
            valueData[0] = 0;
            valueData[1] = 0;
            valueData[2] = params._rootId;
            valueData[3] = params._parentId;

            addressData[0] = params._rootOwner;
            addressData[1] = params._parentOwner;
        }

        require(valueData[0].add(valueData[1]) < feeValue, "feeSplit is error");
    }

    function addWhitelist(address _addToken) external onlyOwner returns (bool) {
        require(_addToken != address(0), "token is the zero address");
        return EnumerableSet.add(_feeWhitelist, _addToken);
    }

    function delWhitelist(address _delToken) external onlyOwner returns (bool) {
        require(_delToken != address(0), "token is the zero address");
        return EnumerableSet.remove(_feeWhitelist, _delToken);
    }

    function isWhitelist(address _token) external view returns (bool) {
        return EnumerableSet.contains(_feeWhitelist, _token);
    }

    function getWhitelistLength() external view returns (uint256) {
        return EnumerableSet.length(_feeWhitelist);
    }

    function getWhitelist(uint256 _index) external view returns (address){
        require(_index <= this.getWhitelistLength() - 1, "index out of bounds");
        return EnumerableSet.at(_feeWhitelist, _index);
    }

    function getTokenQuantity(address tokenIn, address tokenOut, uint256 tokenAmount) external view returns (uint256) {
        if (tokenIn == feeToken) {
            return tokenAmount.mul(supportDeductionFeeValue).div(10000);
        } else if (tokenOut == feeToken) {
            return this.consult(tokenIn, tokenOut, tokenAmount).mul(supportDeductionFeeValue).div(10000);
        } else {
            if (this.isWhitelist(tokenIn)) {
                return this.consult(tokenIn, feeToken, tokenAmount).mul(supportDeductionFeeValue).div(10000);
            }

            if (this.isWhitelist(tokenOut) && !this.isWhitelist(tokenIn)) {
                return this.consult(tokenOut, feeToken, this.consult(tokenIn, tokenOut, tokenAmount)).mul(supportDeductionFeeValue).div(10000);
            }
        }
        return 0;
    }

    function consult(address tokenIn, address tokenOut, uint256 amount) external view returns (uint256){
        if (ICoinSwapV1Factory(factory).getPair(tokenIn, tokenOut) != address(0)) {
            (uint reserveIn, uint reserveOut) = CoinSwapV1Library.getReserves(factory, tokenIn, tokenOut);
            uint numerator = amount.mul(reserveOut);
            uint denominator = reserveIn.add(amount);
            return numerator.div(denominator);
        }
        return 0;
    }
}
