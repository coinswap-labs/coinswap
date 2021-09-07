// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

interface ICoinsToken {
    function mint(address to, uint256 amount) external returns (bool);

    function transfer(address to, uint value) external returns (bool);

    function balanceOf(address owner) external view returns (uint);
}
