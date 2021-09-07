// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import './libraries/SafeMath.sol';
import "./interfaces/ICoinsToken.sol";

contract FundAndTeamVester is Ownable {
    using SafeMath for uint;

    ICoinsToken public coins;
    address public recipient;

    // token tokens created per block
    uint256 public tokenPerBlock;
    // The block number when token mining starts.
    uint256 public startBlock;
    // How many blocks are halved
    uint256 public halvingPeriod = 5256000;

    uint256 public lastUpdate;

    event SetRecipient(address _recipient);
    event SetHalvingPeriod(uint256 _block);
    event Claim(address _to, uint _num);

    constructor(
        ICoinsToken _coins,
        address _recipient,
        uint256 _tokenPerBlock,
        uint256 _startBlock
    ) public {
        require(address(_coins) != address(0), "coins is can not address(0)");
        require(_recipient != address(0), "recipient is can not address(0)");
        coins = _coins;
        recipient = _recipient;
        tokenPerBlock = _tokenPerBlock;
        startBlock = _startBlock;
        lastUpdate = startBlock;
    }

    function setRecipient(address _recipient) external onlyOwner {
        require(address(0) != recipient, "recipient is can not address(0)");
        recipient = _recipient;
        emit SetRecipient(_recipient);
    }

    function setHalvingPeriod(uint256 _block) public onlyOwner {
        halvingPeriod = _block;
        emit SetHalvingPeriod(_block);
    }

    function phase(uint256 blockNumber) public view returns (uint256) {
        if (halvingPeriod == 0) {
            return 0;
        }
        if (blockNumber > startBlock) {
            return (blockNumber.sub(startBlock).sub(1)).div(halvingPeriod);
        }
        return 0;
    }

    function reward(uint256 blockNumber) public view returns (uint256) {
        uint256 _phase = phase(blockNumber);
        return tokenPerBlock.div(2 ** _phase);
    }

    function getTokenBlockReward(uint256 _lastRewardBlock) public view returns (uint256) {
        uint256 blockReward = 0;
        uint256 n = phase(_lastRewardBlock);
        uint256 m = phase(block.number);
        while (n < m) {
            n++;
            uint256 r = n.mul(halvingPeriod).add(startBlock);
            blockReward = blockReward.add((r.sub(_lastRewardBlock)).mul(reward(r)));
            _lastRewardBlock = r;
        }
        blockReward = blockReward.add((block.number.sub(_lastRewardBlock)).mul(reward(block.number)));
        return blockReward;
    }

    function claim() external {
        uint256 tokenReward = getTokenBlockReward(lastUpdate);
        if (tokenReward > 0) {
            coins.mint(recipient, tokenReward);
            lastUpdate = block.number;
        }
        emit Claim(recipient, tokenReward);
    }
}
