// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.6.12;

interface IFeeManager {
    function feeToRate() external view returns (uint256);

    function isOpenSwapMining() external view returns (uint8);

    function supportDeductionFeeValue() external view returns (uint256);

    function supportDeductionFeeSwitches(address from) external view returns (uint8);

    function defaultFeeAddress() external view returns (address);

    function feeToken() external view returns (address);

    function blackHoleAddress() external view returns (address);

    function router() external view returns (address);

    function isWhitelist(address _token) external view returns (bool);

    function feeSplit(address from, uint256 feeValue) external returns (uint[] memory valueData, address[] memory addressData);

    function getTokenQuantity(address tokenIn, address tokenOut, uint256 tokenAmount) external view returns (uint256);
}
