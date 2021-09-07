// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

import "./interfaces/IERC677.sol";
import "./interfaces/IERC2612.sol";

contract CoinsToken is ERC20Capped, IERC677, IERC2612, Ownable {
    using SafeMath for uint256;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _minters;
    //test coin
    uint256 private constant preMineSupply = 10000 * 1e18;

    bytes32 public override DOMAIN_SEPARATOR;

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    // keccak256("Transfer(address owner,address to,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 public constant TRANSFER_TYPEHASH = 0x42ce63790c28229c123925d83266e77c04d28784552ab68b350a9003226cbd59;

    mapping(address => uint256) public override nonces;

    constructor() ERC20Capped(1e27) ERC20("CoinSwap", "COINS") Ownable() public {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name())),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );

        _mint(msg.sender, preMineSupply);
    }

    // mint with coins supply
    function mint(address _to, uint256 _amount) public onlyMinter returns (bool) {
        _mint(_to, _amount);
        return true;
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function transferWithPermit(address owner, address to, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(owner != address(0) && to != address(0), "zero address");
        require(block.timestamp <= deadline || deadline == 0, "expired transfer");

        bytes32 digest = keccak256(
            abi.encodePacked(
                uint16(0x1901),
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(TRANSFER_TYPEHASH, owner, to, value, nonces[owner]++, deadline))
            )
        );

        require(owner == ecrecover(digest, v, r, s), "invalid signature");
        _transfer(owner, to, value);
    }

    // implement the erc-2612
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external override {
        require(owner != address(0), "zero address");
        require(block.timestamp <= deadline || deadline == 0, "permit is expired");

        bytes32 digest = keccak256(
            abi.encodePacked(
                uint16(0x1901),
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );

        require(owner == ecrecover(digest, v, r, s), "invalid signature");
        _approve(owner, spender, value);
    }

    // implement the erc-677
    function transferAndCall(address to, uint value, bytes calldata data) external override returns (bool success) {
        _transfer(msg.sender, to, value);

        return ITransferReceiver(to).onTokenTransfer(msg.sender, value, data);
    }

    function approveAndCall(address spender, uint256 value, bytes calldata data) external override returns (bool success) {
        _approve(msg.sender, spender, value);

        return IApprovalReceiver(spender).onTokenApproval(msg.sender, value, data);
    }

    function addMinter(address _addMinter) public onlyOwner returns (bool) {
        require(_addMinter != address(0), "CoinsToken: _addMinter is the zero address");
        return EnumerableSet.add(_minters, _addMinter);
    }

    function delMinter(address _delMinter) public onlyOwner returns (bool) {
        require(_delMinter != address(0), "CoinsToken: _delMinter is the zero address");
        return EnumerableSet.remove(_minters, _delMinter);
    }

    function getMinterLength() public view returns (uint256) {
        return EnumerableSet.length(_minters);
    }

    function isMinter(address account) public view returns (bool) {
        return EnumerableSet.contains(_minters, account);
    }

    function getMinter(uint256 _index) public view onlyOwner returns (address){
        require(_index <= getMinterLength() - 1, "CoinsToken: index out of bounds");
        return EnumerableSet.at(_minters, _index);
    }

    // modifier for mint function
    modifier onlyMinter() {
        require(isMinter(msg.sender), "caller is not the minter");
        _;
    }
}
