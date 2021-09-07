// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.6.12;

interface IInviteManager {
    function inviteInfo(address trader) external view returns (uint256 rootId, address rootOwner, uint256 parentId, address parentOwner);

    function kickbackDecimals() external view returns (uint256);
    function swapKickback(address trader) external view returns (uint256 rootId, address rootOwner, uint256 rootRate, uint256 parentId, address parentOwner, uint256 parentRate);
    function miningKickback(address trader) external view returns (uint256 rootId, address rootOwner, uint256 rootRate, uint256 parentId, address parentOwner, uint256 parentRate);

    function auctionNode(address owner) external returns (uint256 id);
}
