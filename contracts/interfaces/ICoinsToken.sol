// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface ICoinsToken {
    function mint(address to, uint256 amount) external returns (bool);

    function transfer(address to, uint value) external returns (bool);

    function balanceOf(address owner) external view returns (uint);
}
