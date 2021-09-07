//SPDX-License-Identifier: UNLICENSED
pragma solidity =0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./libraries/TransferHelper.sol";
import "./interfaces/IInviteManager.sol";
import "./interfaces/IERC20.sol";

contract NodeAuction is Ownable {
    using SafeMath for uint256;

    constructor(IERC20 token , IInviteManager manager) public Ownable() {
        feeToken = token;
        inviteManager = manager;
        round = 1;
    }

    IERC20 public feeToken;
    IInviteManager public inviteManager;

    function setFeeToken(IERC20 token) public onlyOwner {
        feeToken = token;
    }

    uint256 public round;

    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public period;
    uint256 public startPrice;
    uint256 public endPrice;

    event AuctionStart(uint256 round, uint256 startBlock, uint256 endBlock, uint256 startPrice, uint256 endPrice);
    event AuctionEnd(uint256 round, uint256 id, address owner, uint256 price);

    function start(uint256 _period, uint256 _startPrice, uint256 _endPrice) public onlyOwner {
        require(_period > 0, "period invalid");
        require(_startPrice > _endPrice, "price invalid");
        startBlock = block.number;
        period = _period;
        endBlock = startBlock.add(period);
        startPrice = _startPrice;
        endPrice = _endPrice;

        emit AuctionStart(round, startBlock, endBlock, startPrice, endPrice);
    }

    function stop() public onlyOwner {
        startBlock = 0;
        period = 0;
        endBlock = 0;
        startPrice = 0;
        endPrice = 0;
    }

    function currentPrice() public view returns (uint256 price) {
        if (startBlock == 0) {
            return 0;
        }
        if (block.number.sub(startBlock) < period) {
            uint256 pricePerBlock = (startPrice.sub(endPrice)).div(period);
            price = startPrice.sub(block.number.sub(startBlock).mul(pricePerBlock));
        } else {
            price = endPrice;
        }
    }

    function auction(uint256 pirceDesired) public {
        require(startBlock > 0 && block.number >= startBlock, "not start");
        uint256 price = currentPrice();
        require(price <= pirceDesired, "price not desired");

        require(feeToken.balanceOf(msg.sender) >= price, "insufficient balance");
        require(feeToken.allowance(msg.sender, address(this)) >= price, "insufficient allownace");

        TransferHelper.safeTransferFrom(address(feeToken), msg.sender, address(this), price);

        IERC20(feeToken).burn(price);

        uint256 id = inviteManager.auctionNode(msg.sender);

        emit AuctionEnd(round, id, msg.sender, price);

        startBlock = block.number + 1;
        endBlock = startBlock.add(period);
        round++;
        emit AuctionStart(round, startBlock, endBlock, startPrice, endPrice);
    }
}
