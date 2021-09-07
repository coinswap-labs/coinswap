// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;


interface IERC677 {
    function approveAndCall(address spender, uint256 value, bytes calldata data) external returns (bool success);
    function transferAndCall(address receiver, uint amount, bytes calldata data) external returns (bool success);
}

interface ITransferReceiver {
    function onTokenTransfer(address, uint, bytes calldata) external returns (bool success);
}

interface IApprovalReceiver {
    function onTokenApproval(address, uint, bytes calldata) external returns (bool success);
}
