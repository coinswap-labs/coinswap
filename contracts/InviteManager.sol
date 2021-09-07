// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./libraries/TransferHelper.sol";
import "./interfaces/IInviteManager.sol";

contract InviteManager is IInviteManager, ERC721, Ownable {
    using SafeMath for uint256;

    event InviteRegistered(address user, uint256 node);
    event NodeRegistered(uint256 id, address owner, uint256 level, uint256 root, uint256 parent);
    event NodeUpdated(uint256 id, string name, string domain, string color, string logo, address operator);

    event SwapKickbackUpdated(uint256 root, uint256 parent);
    event MiningKickbackUpdated(uint256 root, uint256 parent);

    uint256 public override kickbackDecimals = 4;
    uint256 public swapKickbackRoot = 4500;
    uint256 public swapKickbackParent = 2500;
    uint256 public miningKickackRoot = 4500;
    uint256 public miningKickackParent = 2500;

    uint256 private _nextId;

    uint256 public isRootReward = 1;
    mapping(uint256 => uint256) public rootRewardWhiteList;

    struct Node {
        uint256 root;
        uint256 parent;
        uint256 level;
        address owner;
        string name;
        string domain;
        string color;
        string logo;
    }

    mapping(uint256 => Node) _nodes;
    mapping(address => uint256) public invites;

    constructor() public ERC721("CoinSwap V1 Nodes NFT-V1", "COINS-V1-NODES") Ownable() {
        _nextId = 1;
    }

    function setRootReward(uint256 on) public onlyOwner {
        isRootReward = on;
    }

    function setRootRewardWhiteList(uint256 root, uint256 on) public onlyOwner {
        rootRewardWhiteList[root] = on;
    }


    function setSwapKickback(uint256 root, uint256 parent) public onlyOwner {
        require(root > 0 && parent > 0, "rate zero");
        require(root > parent, "root must bigger than parent");
        require(root < (10 ** kickbackDecimals), "root too big");
        swapKickbackRoot = root;
        swapKickbackParent = parent;
        emit SwapKickbackUpdated(root, parent);
    }

    function setMiningKickback(uint256 root, uint256 parent) public onlyOwner {
        require(root > 0 && parent > 0, "rate zero");
        require(root > parent, "root must bigger than parent");
        require(root < (10 ** kickbackDecimals), "root too big");
        miningKickackRoot = root;
        miningKickackParent = parent;
        emit MiningKickbackUpdated(root, parent);
    }


    function _createNode(address owner, uint256 parent) internal returns(uint256 id) {
        uint256 root = _nodes[parent].level == 1 ? parent : _nodes[parent].root;
        uint256 level = _nodes[parent].level + 1;
        _nodes[_nextId] = Node({
            root: root,
            parent: parent,
            level: level,
            owner: owner,
            name: "",
            domain: "",
            color: "",
            logo: ""
        });

        _mint(owner, _nextId);
        emit NodeRegistered(_nextId, owner, level, root, parent);
        id = _nextId;

        _nextId++;
    }

    address public auction;
    function setAuction(address _auction) public onlyOwner {
        auction = _auction;
    }

    function auctionNode(address owner) public override returns (uint256 id) {
        require(msg.sender == auction, "not auction");
        id = _createNode(owner, 0);
    }

    function createNode(address owner) public onlyOwner returns (uint256 id)  {
        id = _createNode(owner, 0);
    }

    function updateNodeInfo(uint256 id, string memory name, string memory domain, string memory color, string memory logo) public {
        require(id > 0 && id < _nextId, "id not exist");
        require(_nodes[id].owner == msg.sender, "not owner");
        _nodes[id].name = name;
        _nodes[id].domain = domain;
        _nodes[id].color = color;
        _nodes[id].logo = logo;

        emit NodeUpdated(id, name, domain, color, logo, msg.sender);
    }
        
    function registerNode(uint256 parent) public {                
        require(parent > 0 && parent < _nextId, "parent not exist");
        _createNode(msg.sender, parent);
    }

    function registerInvite(uint256 id) public  {
        require(id > 0 && id < _nextId, "id not exist");
        require(invites[msg.sender] == 0, "already invited");
        invites[msg.sender] = id;
        emit InviteRegistered(msg.sender, id);
    }

    function nodeInfo(uint256 id)
        external
        view
        returns (
            uint256 root,
            uint256 parent,
            uint256 level,
            address owner,
            string memory name,
            string memory domain,
            string memory color,
            string memory logo
        )
    {
        require(id > 0 && id < _nextId, "id not exist");
        root = _nodes[id].root;
        parent = _nodes[id].parent;
        level = _nodes[id].level;
        owner = _nodes[id].owner;
        name = _nodes[id].name;
        domain = _nodes[id].domain;
        color = _nodes[id].color;
        logo = _nodes[id].logo;
    }

    function inviteInfo(address trader)
        external
        view
        override
        returns (
            uint256 rootId,
            address rootOwner,
            uint256 parentId,
            address parentOwner
        )
    {
        parentId = invites[trader];
        if (parentId != 0) {
            rootId = _nodes[parentId].root;
            rootOwner = _nodes[rootId].owner;

            parentOwner = _nodes[parentId].owner;
        }
    }

    function swapKickback(address trader)
        external
        view
        override
        returns (
            uint256 rootId,
            address rootOwner,
            uint256 rootRate,
            uint256 parentId,
            address parentOwner,
            uint256 parentRate
        )
    {

        parentId = invites[trader];
        if (parentId != 0) {
            uint256 level = _nodes[parentId].level;
            if (level == 1) {
                rootId = parentId;
                rootOwner = _nodes[parentId].owner;
                rootRate = swapKickbackRoot;
            } else {
                parentOwner = _nodes[parentId].owner;
                parentRate = swapKickbackParent;

                uint256 root = _nodes[parentId].root;
                if (isRootReward > 0 &&  (level == 2 || rootRewardWhiteList[root] > 0)) {
                    rootId = root;
                    rootOwner = _nodes[root].owner;
                    rootRate = swapKickbackRoot;
                }
            }
        }
    }

    function miningKickback(address trader)
        external
        view
        override
        returns (
            uint256 rootId,
            address rootOwner,
            uint256 rootRate,
            uint256 parentId,
            address parentOwner,
            uint256 parentRate
        )
    {

        parentId = invites[trader];
        if (parentId != 0) {
            uint256 level = _nodes[parentId].level;
            if (level == 1) {
                rootId = parentId;
                rootOwner = _nodes[parentId].owner;
                rootRate = miningKickackRoot;
            } else {
                parentOwner = _nodes[parentId].owner;
                parentRate = miningKickackParent;

                uint256 root = _nodes[parentId].root;
                if (isRootReward > 0 &&  (level == 2 || rootRewardWhiteList[root] > 0)) {
                    rootId = root;
                    rootOwner = _nodes[root].owner;
                    rootRate = miningKickackRoot;
                }
            }
        }
    }

    function _transferOwner(address from, address to, uint256 tokenId) internal {
        if (_nodes[tokenId].owner == from) {
            _nodes[tokenId].owner = to;
        }
    }


    function transferFrom(address from, address to, uint256 tokenId) public override {
        super.transferFrom(from, to, tokenId);
        _transferOwner(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override {
        super.safeTransferFrom(from, to, tokenId, data);
        _transferOwner(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override {
        super.safeTransferFrom(from, to, tokenId);
        _transferOwner(from, to, tokenId);
    }

    function tokenURI(uint256 tokenId) public view override returns(string memory) {

    }

    function exists(uint256 _id) public view returns (bool){
        return (_id > 0 && _id < _nextId);
    }
}
