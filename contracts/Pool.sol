// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/ICoinsToken.sol";
import "./interfaces/IInviteManager.sol";
import "./interfaces/IOracle.sol";

contract Pool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _multLP;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. tokens to distribute per block.
        uint256 lastRewardBlock;  // Last block number that tokens distribution occurs.
        uint256 accTokenPerShare; // Accumulated tokens per share, times
        uint256 totalAmount;    // Total amount of current pool deposit.
    }

    struct LockInfo {
        uint256 vestingBegin;
        uint256 vestingEnd;
        uint256 lastUpdate;
        uint256 lockAmount;
        uint256 vestedAmount;
    }

    // The token Token!
    ICoinsToken public token;

    // token tokens created per block.
    uint256 public tokenPerBlock;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // pid corresponding address
    mapping(address => uint256) public LpOfPid;
    // Control mining
    bool public paused = false;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    //
    uint256 public startBlock;

    // How many blocks are halved
    uint256 public halvingPeriod = 5256000;

    address public inviteManager;
    // size is zoom 10000
    uint256 public lockUpRate = 4000;
    uint256 public vestingPeriod = 3600;
    uint256 public isAutoSet = 0;
    uint256 public isLock = 0;
    IOracle public oracle;
    bool unlocked = true;

    mapping(address => LockInfo) public lockInfos;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event InviteTransfer(address src, uint256 tokenId, address dst, uint amount);

    constructor(
        ICoinsToken _token,
        IOracle _oracle,
        uint256 _tokenPerBlock,
        uint256 _startBlock
    ) public {
        token = _token;
        oracle = _oracle;
        tokenPerBlock = _tokenPerBlock;
        startBlock = _startBlock;
    }

    modifier lock() {
        require(unlocked, 'LOK');
        unlocked = false;
        _;
        unlocked = true;
    }

    function setHalvingPeriod(uint256 _block) public onlyOwner {
        halvingPeriod = _block;
    }

    function setInviteManager(address _inviteManager) public onlyOwner {
        inviteManager = _inviteManager;
    }

    function setLockUpRate(uint256 _lockUpRate) public onlyOwner {
        require(_lockUpRate >= 0 && _lockUpRate < 10000, "_lockUpRate is error");
        lockUpRate = _lockUpRate;
    }

    function setIsLockSwitch(uint256 _isLock) public onlyOwner {
        require(_isLock == 0 || _isLock == 1, "_isLock is error");
        isLock = _isLock;
    }

    function setAutoSetSwitch(uint256 _isAutoSet) public onlyOwner {
        require(_isAutoSet == 0 || _isAutoSet == 1, "_isAutoSet is error");
        isAutoSet = _isAutoSet;
    }

    function setVestingPeriod(uint256 _vestingPeriod) public onlyOwner {
        vestingPeriod = _vestingPeriod;
    }

    // Set the number of token produced by each block
    function setTokenPerBlock(uint256 _newPerBlock) public onlyOwner {
        massUpdatePools();
        tokenPerBlock = _newPerBlock;
    }

    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function setPause() public onlyOwner {
        paused = !paused;
    }

    function setOracle(IOracle _oracle) public onlyOwner {
        require(address(_oracle) != address(0), "Pool: new oracle is the zero address");
        oracle = _oracle;
    }

    function setStartBlock(uint256 _startBlock) public onlyOwner {
        require(_startBlock > startBlock, "Pool: _startBlock is error");
        startBlock = _startBlock;
    }


    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        require(address(_lpToken) != address(0), "_lpToken is the zero address");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accTokenPerShare : 0,
        totalAmount : 0
        }));
        LpOfPid[address(_lpToken)] = poolLength() - 1;
    }

    // Update the given pool's token allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
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

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.totalAmount;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 blockReward = getTokenBlockReward(pool.lastRewardBlock);
        if (blockReward <= 0) {
            return;
        }
        uint256 tokenReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
        bool minRet = token.mint(address(this), tokenReward);
        if (minRet) {
            pool.accTokenPerShare = pool.accTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        }
        pool.lastRewardBlock = block.number;
    }

    // View function to see pending tokens on frontend.
    function pending(uint256 _pid, address _user) external view returns (uint256, uint256){
        uint256 tokenAmount = pendingToken(_pid, _user);
        return (tokenAmount, 0);
    }

    // View function to see pending tokens on frontend.
    function pendingInfo(uint256 _pid, address _user)
    external
    view
    returns (uint256 rewardValue, uint256 newLockValue, uint oldLockValue, uint unLockValue, uint canClaim){
        uint256 tokenAmount = pendingToken(_pid, _user);
        newLockValue = 0;
        if (isLock == 1) {
            if (isAutoSet == 1) {
                uint autoRate = oracle.consultPriceDecPercent();
                newLockValue = tokenAmount.mul(autoRate) / 10000;
            } else {
                newLockValue = tokenAmount.mul(lockUpRate) / 10000;
            }
        }
        rewardValue = tokenAmount.sub(newLockValue);
        oldLockValue = _vest(_user);
        unLockValue = _vested(_user);
        canClaim = rewardValue.add(unLockValue);
    }

    function pendingToken(uint256 _pid, address _user) private view returns (uint256){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = pool.totalAmount;
        if (user.amount > 0) {
            if (block.number > pool.lastRewardBlock) {
                uint256 blockReward = getTokenBlockReward(pool.lastRewardBlock);
                uint256 tokenReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
                accTokenPerShare = accTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));

                Params memory params = Params(0, address(0), 0, 0, address(0), 0);
                (params._rootId, params._rootOwner, params._rootRate, params._parentId, params._parentOwner, params._parentRate) = IInviteManager(inviteManager).miningKickback(_user);
                uint[]  memory resultData = rewardSplit(user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt), params);
                return resultData[2];
            }
            if (block.number == pool.lastRewardBlock) {
                Params memory params = Params(0, address(0), 0, 0, address(0), 0);
                (params._rootId, params._rootOwner, params._rootRate, params._parentId, params._parentOwner, params._parentRate) = IInviteManager(inviteManager).miningKickback(_user);
                uint[]  memory resultData = rewardSplit(user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt), params);
                return resultData[2];
            }
        }
        return 0;
    }

    // Deposit LP tokens to HecoPool for token allocation.
    function deposit(uint256 _pid, uint256 _amount) public notPause lock() {
        depositToken(_pid, _amount, msg.sender);
    }

    function depositToken(uint256 _pid, uint256 _amount, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pendingAmount = user.amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt);
            if (pendingAmount > 0) {
                safeTokenTransfer(_user, pendingAmount);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(_user, address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.totalAmount = pool.totalAmount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        emit Deposit(_user, _pid, _amount);
    }

    // Withdraw LP tokens from HecoPool.
    function withdraw(uint256 _pid, uint256 _amount) public notPause lock() {
        withdrawToken(_pid, _amount, msg.sender);
    }

    function withdrawToken(uint256 _pid, uint256 _amount, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        require(user.amount >= _amount, "withdrawToken: not good");
        updatePool(_pid);
        uint256 pendingAmount = user.amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt);
        if (pendingAmount > 0) {
            safeTokenTransfer(_user, pendingAmount);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalAmount = pool.totalAmount.sub(_amount);
            pool.lpToken.safeTransfer(_user, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        emit Withdraw(_user, _pid, _amount);
    }

    // The user withdraws all the transaction rewards of the pool
    function takerReward() public notPause lock() {
        uint256 userReword;
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            UserInfo storage user = userInfo[pid][msg.sender];
            updatePool(pid);
            uint256 pendingAmount = user.amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt);
            if (pendingAmount > 0) {
                userReword += pendingAmount;
            }
            user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        }
        if (userReword <= 0) {
            return;
        }
        safeTokenTransfer(msg.sender, userReword);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public notPause lock() {
        emergencyWithdrawToken(_pid, msg.sender);
    }

    function emergencyWithdrawToken(uint256 _pid, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(_user, amount);
        pool.totalAmount = pool.totalAmount.sub(amount);
        emit EmergencyWithdraw(_user, _pid, amount);
    }

    struct Params {
        uint256 _rootId;
        address _rootOwner;
        uint256 _rootRate;
        uint256 _parentId;
        address _parentOwner;
        uint256 _parentRate;
    }

    // Safe token transfer function, just in case if rounding error causes pool to not have enough tokens.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = token.balanceOf(address(this));
        if (_amount > tokenBal) {
            _amount = tokenBal;
        }
        Params memory params = Params(0, address(0), 0, 0, address(0), 0);
        (params._rootId, params._rootOwner, params._rootRate, params._parentId, params._parentOwner, params._parentRate) = IInviteManager(inviteManager).miningKickback(_to);
        uint[]  memory resultData = rewardSplit(_amount, params);
        if (resultData[0] > 0) {
            token.transfer(params._rootOwner, resultData[0]);
            emit InviteTransfer(_to, params._rootId, params._rootOwner, resultData[0]);
        }
        if (resultData[1] > 0) {
            token.transfer(params._parentOwner, resultData[1]);
            emit InviteTransfer(_to, params._parentId, params._parentOwner, resultData[1]);
        }
        if (resultData[2] > 0) {
            lockReward(_to, resultData[2]);
        }
    }

    function rewardSplit(uint256 _amount, Params memory params) internal view returns (uint[]  memory resultData){
        require(inviteManager != address(0), "inviteManger is not zero address");

        resultData = new uint[](3);
        bool isRootHave = params._rootOwner != address(0) && params._rootId > 0 && params._rootRate > 0;
        bool isParentHave = params._parentOwner != address(0) && params._parentId > 0 && params._parentRate > 0;

        uint256 parentRewardValue;
        uint256 rootRewardValue;
        if (isRootHave && isParentHave) {
            parentRewardValue = _amount.mul(params._parentRate).div(10 ** IInviteManager(inviteManager).kickbackDecimals());
            rootRewardValue = _amount.mul(params._rootRate).div(10 ** IInviteManager(inviteManager).kickbackDecimals()).sub(parentRewardValue);
            resultData[0] = rootRewardValue;
            resultData[1] = parentRewardValue;
            resultData[2] = _amount.sub(rootRewardValue).sub(parentRewardValue);
        }

        if (isParentHave && !isRootHave) {
            parentRewardValue = _amount.mul(params._parentRate).div(10 ** IInviteManager(inviteManager).kickbackDecimals());
            resultData[0] = 0;
            resultData[1] = parentRewardValue;
            resultData[2] = _amount.sub(parentRewardValue);
        }

        if (!isParentHave && isRootHave) {
            rootRewardValue = _amount.mul(params._rootRate) .div(10 ** IInviteManager(inviteManager).kickbackDecimals());
            resultData[0] = rootRewardValue;
            resultData[1] = 0;
            resultData[2] = _amount.sub(rootRewardValue);
        }

        if (!isParentHave && !isRootHave) {
            resultData[0] = 0;
            resultData[1] = 0;
            resultData[2] = _amount;
        }
    }

    function lockReward(address to, uint256 _amount) internal {
        if (isLock == 1) {
            uint256 lockValue;
            if (isAutoSet == 1) {
                uint autoRate = oracle.consultPriceDecPercent();
                lockValue = _amount.mul(autoRate) / 10000;
            } else {
                lockValue = _amount.mul(lockUpRate) / 10000;
            }
            if (lockValue > 0) {
                LockInfo storage info = lockInfos[to];
                if (info.lockAmount > 0) {
                    if (block.number <= info.vestingBegin) {
                        info.lockAmount = info.lockAmount.add(lockValue);
                        info.vestedAmount = 0;
                        token.transfer(to, _amount.sub(lockValue));
                    } else if (block.number >= info.vestingEnd) {
                        token.transfer(to, info.lockAmount.sub(info.vestedAmount).add(_amount).sub(lockValue));
                        //new lock
                        info.lockAmount = lockValue;
                        info.vestedAmount = 0;
                        info.vestingBegin = block.number;
                        info.vestingEnd = info.vestingBegin.add(vestingPeriod);
                        info.lastUpdate = info.vestingBegin;
                    } else {
                        uint canVestAmount = info.lockAmount.mul(block.number.sub(info.lastUpdate)).div(info.vestingEnd.sub(info.vestingBegin));
                        require(info.lockAmount.sub(info.vestedAmount) >= canVestAmount, "canVestAmount is error");
                        token.transfer(to, canVestAmount.add(_amount).sub(lockValue));
                        //update lock
                        info.lockAmount = lockValue.add(info.lockAmount.sub(info.vestedAmount).sub(canVestAmount));
                        info.vestedAmount = 0;
                        info.vestingBegin = block.number;
                        info.vestingEnd = info.vestingBegin.add(vestingPeriod);
                        info.lastUpdate = info.vestingBegin;
                    }
                } else {
                    info.lockAmount = lockValue;
                    info.vestingBegin = block.number;
                    info.vestingEnd = info.vestingBegin .add(vestingPeriod);
                    info.lastUpdate = info.vestingBegin;
                    info.vestedAmount = 0;
                    token.transfer(to, _amount.sub(lockValue));
                }
            } else {
                token.transfer(to, _amount);
            }
        } else {
            token.transfer(to, _amount);
        }
    }

    function getPoolInfo(uint256 _pid) external view returns (address _lpToken, uint256 _allocPoint, uint256 _lastRewardBlock, uint256 _accTokenPerShare, uint256 _totalAmount) {
        PoolInfo memory pool = poolInfo[_pid];
        _lpToken = address(pool.lpToken);
        _allocPoint = pool.allocPoint;
        _lastRewardBlock = pool.lastRewardBlock;
        _accTokenPerShare = pool.accTokenPerShare;
        _totalAmount = pool.totalAmount;
    }

    function getUserInfo(uint256 _pid, address _user) external view returns (uint256 _amount, uint256 _rewardDebt) {
        UserInfo memory user = userInfo[_pid][_user];
        _amount = user.amount;
        _rewardDebt = user.rewardDebt;
    }

    modifier notPause() {
        require(paused == false, "Mining has been suspended");
        _;
    }

    function vested() external view returns (uint256) {
        return _vested(msg.sender);
    }

    function _vested(address owner) internal view returns (uint256) {
        LockInfo memory info = lockInfos[owner];

        if (info.lockAmount == 0 || block.number < info.vestingBegin) {
            return 0;
        }

        if (block.number >= info.vestingEnd) {
            return info.lockAmount.sub(info.vestedAmount);
        } else {
            return info.lockAmount.mul(block.number.sub(info.lastUpdate)).div(info.vestingEnd.sub(info.vestingBegin));
        }
    }

    function vest() external view returns (uint256) {
        return _vest(msg.sender);
    }

    //locking;
    function _vest(address _user) internal view returns (uint256) {
        LockInfo memory info = lockInfos[_user];
        if (info.vestingEnd <= block.number || info.vestingEnd <= info.lastUpdate || info.lockAmount == 0) {
            return 0;
        }
        return info.lockAmount.sub(_vested(_user)).sub(info.vestedAmount);
    }

    function getRealReward(uint256 _pid) external view returns (uint256){
        uint256 pendingValue = pendingToken(_pid, msg.sender);
        LockInfo memory info = lockInfos[msg.sender];

        return pendingValue.add(info.lockAmount).sub(info.vestedAmount);
    }

    function claim() external lock() {
        uint256 amount = _vested(msg.sender);

        if (amount > 0) {
            LockInfo storage info = lockInfos[msg.sender];

            info.vestedAmount = info.vestedAmount.add(amount);
            info.lastUpdate = block.number;

            if (block.number >= info.vestingEnd) {
                info.lastUpdate = info.vestingEnd;
                info.lockAmount = 0;
                info.vestedAmount = 0;
            }

            token.transfer(msg.sender, amount);
        }
    }
}
