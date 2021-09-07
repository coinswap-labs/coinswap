// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "./interfaces/IERC20.sol";
import "./libraries/SafeMath.sol";
import "./libraries/CoinSwapV1Library.sol";
import "./interfaces/ICoinSwapV1Factory.sol";
import "./interfaces/ICoinSwapV1Pair.sol";
import "./interfaces/ICoinsToken.sol";
import "./interfaces/IOracle.sol";

contract SwapMining is Ownable {
    using SafeMath for uint;
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _whitelist;

    // token tokens created per block
    uint256 public tokenPerBlock;
    // The block number when token mining starts.
    uint256 public startBlock;
    // How many blocks are halved
    uint256 public halvingPeriod = 5256000;
    // Total allocation points
    uint256 public totalAllocPoint = 0;
    IOracle public oracle;
    // router address
    address public router;
    // factory address
    ICoinSwapV1Factory public factory;
    // token token address
    ICoinsToken public token;
    // Calculate price based on HUSD
    address public targetToken;
    // pair corresponding pid
    mapping(address => uint256) public pairOfPid;

    constructor(
        ICoinsToken _token,
        ICoinSwapV1Factory _factory,
        IOracle _oracle,
        address _router,
        address _targetToken,
        uint256 _tokenPerBlock,
        uint256 _startBlock
    ) public {
        token = _token;
        factory = _factory;
        oracle = _oracle;
        router = _router;
        targetToken = _targetToken;
        tokenPerBlock = _tokenPerBlock;
        startBlock = _startBlock;
    }

    struct UserInfo {
        uint256 quantity;       // How many LP tokens the user has provided
        uint256 blockNumber;    // Last transaction block
    }

    struct PoolInfo {
        address pair;           // Trading pairs that can be mined
        uint256 quantity;       // Current amount of LPs
        uint256 totalQuantity;  // All quantity
        uint256 allocPoint;     // How many allocation points assigned to this pool
        uint256 allocTokenAmount; // How many tokens
        uint256 lastRewardBlock;// Last transaction block
    }

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    bool unlocked = true;

    event SetHalvingPeriod(uint _block);
    event SetRouter(address _router);
    event SetTokenPerBlock(uint _num);
    event SetOracle(address _oracle);
    event SetStartBlock(uint _startBlock);
    event AddPair(uint256 _allocPoint, address _lpToken, bool _withUpdate);
    event SetPair(uint256 _pid, uint256 _allocPoint, bool _withUpdate);
    event AddWhitelist(address _token);
    event DelWhitelist(address _token);
    event Mint(uint pid, uint amount);
    event Swap(address account, address input, address output, uint256 amount);
    event TakerWithdraw(address account, uint amount);

    modifier lock() {
        require(unlocked, 'LOK');
        unlocked = false;
        _;
        unlocked = true;
    }

    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }


    function addPair(uint256 _allocPoint, address _pair, bool _withUpdate) public onlyOwner {
        require(_pair != address(0), "_pair is the zero address");
        if (_withUpdate) {
            massMintPools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        pair : _pair,
        quantity : 0,
        totalQuantity : 0,
        allocPoint : _allocPoint,
        allocTokenAmount : 0,
        lastRewardBlock : lastRewardBlock
        }));
        pairOfPid[_pair] = poolLength() - 1;
        emit AddPair(_allocPoint, _pair, _withUpdate);
    }

    // Update the allocPoint of the pool
    function setPair(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massMintPools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        emit SetPair(_pid, _allocPoint, _withUpdate);
    }

    // Set the number of token produced by each block
    function setTokenPerBlock(uint256 _newPerBlock) public onlyOwner {
        massMintPools();
        tokenPerBlock = _newPerBlock;
        emit SetTokenPerBlock(_newPerBlock);
    }

    // Only tokens in the whitelist can be mined token
    function addWhitelist(address _addToken) public onlyOwner returns (bool) {
        require(_addToken != address(0), "SwapMining: token is the zero address");
        emit AddWhitelist(_addToken);
        return EnumerableSet.add(_whitelist, _addToken);
    }

    function delWhitelist(address _delToken) public onlyOwner returns (bool) {
        require(_delToken != address(0), "SwapMining: token is the zero address");
        emit DelWhitelist(_delToken);
        return EnumerableSet.remove(_whitelist, _delToken);
    }

    function getWhitelistLength() public view returns (uint256) {
        return EnumerableSet.length(_whitelist);
    }

    function isWhitelist(address _token) public view returns (bool) {
        return EnumerableSet.contains(_whitelist, _token);
    }

    function getWhitelist(uint256 _index) public view returns (address){
        require(_index <= getWhitelistLength() - 1, "SwapMining: index out of bounds");
        return EnumerableSet.at(_whitelist, _index);
    }

    function setHalvingPeriod(uint256 _block) public onlyOwner {
        halvingPeriod = _block;
        emit SetHalvingPeriod(_block);
    }

    function setRouter(address newRouter) public onlyOwner {
        require(newRouter != address(0), "SwapMining: new router is the zero address");
        router = newRouter;
        emit SetRouter(newRouter);
    }

    function setOracle(IOracle _oracle) public onlyOwner {
        require(address(_oracle) != address(0), "SwapMining: new oracle is the zero address");
        oracle = _oracle;
        emit SetOracle(address(_oracle));
    }

    function setStartBlock(uint256 _startBlock) public onlyOwner {
        require(_startBlock > startBlock, "SwapMining: _startBlock is error");
        startBlock = _startBlock;
        emit SetStartBlock(_startBlock);
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

    function phase() public view returns (uint256) {
        return phase(block.number);
    }

    function reward(uint256 blockNumber) public view returns (uint256) {
        uint256 _phase = phase(blockNumber);
        return tokenPerBlock.div(2 ** _phase);
    }

    function reward() public view returns (uint256) {
        return reward(block.number);
    }

    // Rewards for the current block
    function getTokenReward(uint256 _lastRewardBlock) public view returns (uint256) {
        require(_lastRewardBlock <= block.number, "SwapMining: must little than the current block number");
        uint256 blockReward = 0;
        uint256 n = phase(_lastRewardBlock);
        uint256 m = phase(block.number);
        // If it crosses the cycle
        while (n < m) {
            n++;
            // Get the last block of the previous cycle
            uint256 r = n.mul(halvingPeriod).add(startBlock);
            // Get rewards from previous periods
            blockReward = blockReward.add((r.sub(_lastRewardBlock)).mul(reward(r)));
            _lastRewardBlock = r;
        }
        blockReward = blockReward.add((block.number.sub(_lastRewardBlock)).mul(reward(block.number)));
        return blockReward;
    }

    // Update all pools Called when updating allocPoint and setting new blocks
    function massMintPools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            mint(pid);
        }
    }

    function mint(uint256 _pid) public returns (bool) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return false;
        }
        uint256 blockReward = getTokenReward(pool.lastRewardBlock);
        if (blockReward <= 0) {
            return false;
        }
        // Calculate the rewards obtained by the pool based on the allocPoint
        uint256 tokenReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
        token.mint(address(this), tokenReward);
        // Increase the number of tokens in the current pool
        pool.allocTokenAmount = pool.allocTokenAmount.add(tokenReward);
        pool.lastRewardBlock = block.number;
        emit Mint(_pid, tokenReward);
        return true;
    }

    // swapMining only router
    function swap(address account, address input, address output, uint256 amount) external onlyRouter returns (bool) {
        require(account != address(0), "SwapMining: taker swap account is the zero address");
        require(input != address(0), "SwapMining: taker swap input is the zero address");
        require(output != address(0), "SwapMining: taker swap output is the zero address");

        if (poolLength() <= 0) {
            return false;
        }

        if (!isWhitelist(input) || !isWhitelist(output)) {
            return false;
        }

        address pair = CoinSwapV1Library.pairFor(address(factory), input, output);

        PoolInfo storage pool = poolInfo[pairOfPid[pair]];
        // If it does not exist or the allocPoint is 0 then return
        if (pool.pair != pair || pool.allocPoint <= 0) {
            return false;
        }

        uint256 quantity = getQuantity(output, amount, targetToken);
        if (quantity <= 0) {
            return false;
        }

        mint(pairOfPid[pair]);
        pool.quantity = pool.quantity.add(quantity);
        pool.totalQuantity = pool.totalQuantity.add(quantity);
        UserInfo storage user = userInfo[pairOfPid[pair]][account];
        user.quantity = user.quantity.add(quantity);
        user.blockNumber = block.number;
        emit Swap(account, input, output, amount);
        return true;
    }

    // The user withdraws all the transaction rewards of the pool
    function takerWithdraw() public lock {
        uint256 userSub;
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            UserInfo storage user = userInfo[pid][msg.sender];
            if (user.quantity > 0) {
                mint(pid);
                // The reward held by the user in this pool
                uint256 userReward = pool.allocTokenAmount.mul(user.quantity).div(pool.quantity);
                pool.quantity = pool.quantity.sub(user.quantity);
                pool.allocTokenAmount = pool.allocTokenAmount.sub(userReward);
                user.quantity = 0;
                user.blockNumber = block.number;
                userSub = userSub.add(userReward);
            }
        }
        if (userSub <= 0) {
            return;
        }
        token.transfer(msg.sender, userSub);
    }

    // Get rewards from users in the current pool
    function getUserReward(uint256 _pid) public view returns (uint256 userSub, uint256 quantity){
        require(_pid <= poolInfo.length - 1, "SwapMining: Not find this pool");
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][msg.sender];
        if (user.quantity > 0) {
            uint256 blockReward = getTokenReward(pool.lastRewardBlock);
            uint256 tokenReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
            userSub = userSub.add((pool.allocTokenAmount.add(tokenReward)).mul(user.quantity).div(pool.quantity));
        }
        //Token available to users, User transaction amount
        quantity = user.quantity;
        return (userSub, quantity);
    }

    // Get rewards from users in the current pool
    function getUserAllReward() public view returns (uint256 userAllSub, uint256 userAllQuantity){

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo memory pool = poolInfo[pid];
            UserInfo memory user = userInfo[pid][msg.sender];
            if (user.quantity > 0) {
                uint256 blockReward = getTokenReward(pool.lastRewardBlock);
                uint256 tokenReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
                userAllSub = userAllSub.add((pool.allocTokenAmount.add(tokenReward)).mul(user.quantity).div(pool.quantity));
                userAllQuantity = userAllQuantity.add(user.quantity);
            }
        }

        //Token available to users, User transaction amount
        return (userAllSub, userAllQuantity);
    }

    // Get details of the pool
    function getPoolInfo(uint256 _pid) public view returns (address, address, uint256, uint256, uint256, uint256){
        require(_pid <= poolInfo.length - 1, "SwapMining: Not find this pool");
        PoolInfo memory pool = poolInfo[_pid];
        address token0 = ICoinSwapV1Pair(pool.pair).token0();
        address token1 = ICoinSwapV1Pair(pool.pair).token1();
        uint256 tokenAmount = pool.allocTokenAmount;
        uint256 blockReward = getTokenReward(pool.lastRewardBlock);
        uint256 tokenReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
        tokenAmount = tokenAmount.add(tokenReward);
        //token0,token1,Pool remaining reward,Total /Current transaction volume of the pool
        return (token0, token1, tokenAmount, pool.totalQuantity, pool.quantity, pool.allocPoint);
    }

    modifier onlyRouter() {
        require(msg.sender == router, "SwapMining: caller is not the router");
        _;
    }

    function getQuantity(address outputToken, uint256 outputAmount, address anchorToken) public view returns (uint256) {
        uint256 quantity = 0;
        if (outputToken == anchorToken) {
            quantity = outputAmount;
        } else if (ICoinSwapV1Factory(factory).getPair(outputToken, anchorToken) != address(0)) {
            quantity = IOracle(oracle).consult(outputToken, outputAmount, anchorToken);
        } else {
            uint256 length = getWhitelistLength();
            for (uint256 index = 0; index < length; index++) {
                address intermediate = getWhitelist(index);
                if (ICoinSwapV1Factory(factory).getPair(outputToken, intermediate) != address(0) && ICoinSwapV1Factory(factory).getPair(intermediate, anchorToken) != address(0)) {
                    uint256 interQuantity = IOracle(oracle).consult(outputToken, outputAmount, intermediate);
                    quantity = IOracle(oracle).consult(intermediate, interQuantity, anchorToken);
                    break;
                }
            }
        }
        return quantity;
    }

    function getUserInfo(uint256 _pid, address _user) external view returns (uint256 _quantity, uint256 _blockNumber) {
        UserInfo memory user = userInfo[_pid][_user];
        _quantity = user.quantity;
        _blockNumber = user.blockNumber;
    }
}
