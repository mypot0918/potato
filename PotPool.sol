// SPDX-License-Identifier: MIT

pragma solidity 0.5.8;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./PotToken.sol";

contract PotPool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        IERC20 token;
        uint256 startBlock;
        uint256 endBlock;
        uint256 potPerBlock;
        uint256 lastRewardBlock;
        uint256 accPotPerShare;
    }

    PotToken public pot;

    PoolInfo[] public pools;
    mapping (uint256 => mapping (address => UserInfo)) public users;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(PotToken _pot) public {
        pot = _pot;
    }

    modifier checkPool(uint256 _pid) {
        require(address(pools[_pid].token) != address(0), "pool not exist");
        _;
    }

    function poolLength() external view returns (uint256) {
        return pools.length;
    }

    function addPool(IERC20 _token, uint256 _startBlock, uint256 _endBlock, uint256 _potPerBlock) public onlyOwner {
        for (uint i = 0; i < pools.length; ++i) {
            require(address(pools[i].token) != address(_token), "pool already exist");
        }
        uint256 lastRewardBlock = block.number > _startBlock ? block.number : _startBlock;
        pools.push(PoolInfo({
            token: _token,
            startBlock: _startBlock,
            endBlock: _endBlock,
            potPerBlock: _potPerBlock,
            lastRewardBlock: lastRewardBlock,
            accPotPerShare: 0
        }));
    }

    function getTotalReward(PoolInfo storage pool) internal view returns (uint256 reward) {
        if (block.number <= pool.lastRewardBlock) {
            return 0;
        }
        uint256 from = pool.lastRewardBlock;
        uint256 to = block.number < pool.endBlock ? block.number : pool.endBlock;
        if (from >= to) {
            return 0;
        }
        uint256 multiplier = to.sub(from);
        return multiplier.mul(pool.potPerBlock);
    }

    function updatePool(uint256 _pid) public checkPool(_pid) {
        PoolInfo storage pool = pools[_pid];
        if (block.number <= pool.lastRewardBlock || pool.lastRewardBlock >= pool.endBlock) {
            return;
        }

        uint256 totalStake = pool.token.balanceOf(address(this));
        if (totalStake == 0) {
            pool.lastRewardBlock = block.number < pool.endBlock ? block.number : pool.endBlock;
            return;
        }
        
        uint256 reward = getTotalReward(pool);
        pot.mint(address(this), reward);
        pool.accPotPerShare = pool.accPotPerShare.add(reward.mul(1e12).div(totalStake));
        pool.lastRewardBlock = block.number < pool.endBlock ? block.number : pool.endBlock;
    }

    function pendingPot(uint256 _pid, address _user) external view checkPool(_pid) returns (uint256) {
        PoolInfo storage pool = pools[_pid];
        UserInfo storage user = users[_pid][_user];
        uint256 accPotPerShare = pool.accPotPerShare;
        uint256 totalStake = pool.token.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && totalStake > 0) {
            uint256 reward = getTotalReward(pool);
            accPotPerShare = accPotPerShare.add(reward.mul(1e12).div(totalStake));
        }
        return user.amount.mul(accPotPerShare).div(1e12).sub(user.rewardDebt);
    }

    function deposit(uint256 _pid, uint256 _amount) public checkPool(_pid) {
        PoolInfo storage pool = pools[_pid];
        UserInfo storage user = users[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            require(block.number < pool.endBlock, "pool has closed");
            uint256 pending = user.amount.mul(pool.accPotPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safePotTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.token.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPotPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public checkPool(_pid) {
        PoolInfo storage pool = pools[_pid];
        UserInfo storage user = users[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: insufficient balance");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accPotPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safePotTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.token.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPotPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function safePotTransfer(address _to, uint256 _amount) internal {
        uint256 potBalance = pot.balanceOf(address(this));
        if (_amount > potBalance) {
            pot.transfer(_to, potBalance);
        } else {
            pot.transfer(_to, _amount);
        }
    }
}