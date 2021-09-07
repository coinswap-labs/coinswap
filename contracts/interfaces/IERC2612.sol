// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

interface IERC2612 {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function nonces(address owner) external view returns (uint256);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
}
