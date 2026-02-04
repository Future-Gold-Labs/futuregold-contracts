// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract GHKMiningPool is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // 质押记录结构体
    struct Stake {
        uint256 amount; // 质押金额
        uint256 startTime; // 质押开始时间
        uint256 unlockTime; // 可释放时间
        uint256 userRewardRate; // 该笔质押时的累积奖励率
    }

    // 用户的质押记录列表
    mapping(address => Stake[]) public stakes;
    // 全局累积奖励率，扩大 1e18
    uint256 public cumulativeRewardRate;
    // 上次更新时间
    uint256 public lastUpdateTime;
    // 当前每日奖励率
    uint256 public currentRewardPerDay;
    //最小质押GHK数量，以 代币精度位
    uint256 public MIN_STAKE_GHK_AMOUNT;

    // 锁定周期
    uint256 public LOCK_PERIOD;
    // 代币合约地址
    IERC20 public ghkToken; // $GHK 代币
    IERC20 public ghkeToken; // $GHKE 代币

    // 暂停质押
    bool public stop;

    // 事件定义
    event Staked(address indexed user, uint256 amount, uint256 index);
    event RewardClaimed(address indexed user, uint256 reward, uint256 index);
    event Unstaked(address indexed user, uint256 amount, uint256 index);
    event RewardRateUpdated(uint256 newRate);
    event MinStakeGhkAmountUpdated(uint256 indexed oldVal, uint256 newVal);
    event LockPeriodUpdated(uint256 indexed oldVal, uint256 newVal);
    event StopStatusChanged(bool indexed stop);
    event EmergencyWithdraw(address indexed coin, address to, uint256 amount);

    function initialize(
        address _ghkToken,
        address _ghkeToken
    ) public initializer {
        __Ownable_init(msg.sender);
        ghkToken = IERC20(_ghkToken);
        ghkeToken = IERC20(_ghkeToken);
        currentRewardPerDay = 1e17; // 0.1
        lastUpdateTime = block.timestamp;
        // 锁定周期
        LOCK_PERIOD = 90 days;
        MIN_STAKE_GHK_AMOUNT = 1e18; // 1
    }

    // 更新累积奖励率
    function updateCumulativeRewardRate() internal {
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        if (timeElapsed > 0 && currentRewardPerDay > 0) {
            cumulativeRewardRate +=
                (timeElapsed * currentRewardPerDay * 1e18) /
                1 days; // 乘以 1e18 以确保 cumulativeRewardRate 至少有 18 位精度，避免因精度不足导致数据不正确
            lastUpdateTime = block.timestamp;
        }
    }

    // 质押功能
    function deposit(uint256 amount) external {
        require(!stop, "stopped");
        require(
            amount >= MIN_STAKE_GHK_AMOUNT,
            "Stake amount must be greater than 0"
        );

        // 更新累积奖励率
        updateCumulativeRewardRate();

        // 转移 $GHK 代币
        ghkToken.safeTransferFrom(msg.sender, address(this), amount);

        // 添加质押记录
        stakes[msg.sender].push(
            Stake({
                amount: amount,
                startTime: block.timestamp,
                unlockTime: block.timestamp + LOCK_PERIOD,
                userRewardRate: cumulativeRewardRate
            })
        );

        emit Staked(msg.sender, amount, stakes[msg.sender].length - 1);
    }

    // 提取单个奖励功能
    function claimReward(uint256 index) external {
        require(index < stakes[msg.sender].length, "Invalid stake index");
        Stake memory stakeRecord = stakes[msg.sender][index];
        require(
            block.timestamp >= stakeRecord.unlockTime,
            "Stake is still locked"
        );
        require(stakeRecord.amount > 0, "No active stake at this index");

        // 更新累积奖励率
        updateCumulativeRewardRate();

        // 计算单个记录的奖励
        uint256 reward = (stakeRecord.amount *
            (cumulativeRewardRate - stakeRecord.userRewardRate)) /
            1e18 /
            1e18;
        require(reward > 0, "No reward to claim");

        // 转移 $GHKE 代币
        ghkeToken.safeTransfer(msg.sender, reward);

        // 更新该质押记录的奖励率
        stakes[msg.sender][index].userRewardRate = cumulativeRewardRate;

        emit RewardClaimed(msg.sender, reward, index);
    }

    // 解锁并提取本金
    function withdraw(uint256 index) external {
        require(index < stakes[msg.sender].length, "Invalid stake index");
        Stake memory stakeRecord = stakes[msg.sender][index];
        require(stakeRecord.amount > 0, "Stake already withdrawn");

        // 更新累积奖励率
        updateCumulativeRewardRate();

        if (block.timestamp >= stakeRecord.unlockTime) {
            // 计算奖励
            uint256 reward = (stakeRecord.amount *
                (cumulativeRewardRate - stakeRecord.userRewardRate)) /
                1e18 /
                1e18;

            if (reward > 0) {
                ghkeToken.safeTransfer(msg.sender, reward);
                emit RewardClaimed(msg.sender, reward, index);
            }
        }

        // 提取本金
        uint256 amount = stakeRecord.amount;
        stakes[msg.sender][index].amount = 0;
        ghkToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount, index);
    }

    // 紧急提取，只能提取本金
    function emergencyWithdraw(uint256 index) external {
        require(index < stakes[msg.sender].length, "Invalid stake index");
        Stake memory stakeRecord = stakes[msg.sender][index];
        require(stakeRecord.amount > 0, "Stake already withdrawn");

        // 提取本金
        uint256 amount = stakeRecord.amount;
        stakes[msg.sender][index].amount = 0;
        ghkToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount, index);
    }

    // 计算单个质押记录的奖励
    function calculateReward(
        address user,
        uint256 index
    ) public view returns (uint256) {
        require(index < stakes[user].length, "Invalid stake index");
        Stake memory stakeRecord = stakes[user][index];
        require(stakeRecord.amount > 0, "No active stake at this index");

        uint256 tempCumulativeRewardRate = cumulativeRewardRate;
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        if (timeElapsed > 0 && currentRewardPerDay > 0) {
            tempCumulativeRewardRate +=
                (timeElapsed * currentRewardPerDay * 1e18) /
                1 days;
        }

        uint256 reward = (stakeRecord.amount *
            (tempCumulativeRewardRate - stakeRecord.userRewardRate)) /
            1e18 /
            1e18;
        return reward;
    }

    // 更新每日奖励率（仅管理员）
    function updateRewardRate(uint256 newRate) public onlyOwner {
        updateCumulativeRewardRate();
        currentRewardPerDay = newRate;
        emit RewardRateUpdated(newRate);
    }

    //最小质押GHK数量更新（仅管理员）
    function setMinStakeGhkAmount(uint256 _newVal) external onlyOwner {
        uint256 oldValue = MIN_STAKE_GHK_AMOUNT;
        MIN_STAKE_GHK_AMOUNT = _newVal;
        emit MinStakeGhkAmountUpdated(oldValue, _newVal);
    }

    //锁定周期
    function setLockPeriod(uint256 _newVal) external onlyOwner {
        uint256 oldValue = LOCK_PERIOD;
        LOCK_PERIOD = _newVal;
        emit LockPeriodUpdated(oldValue, _newVal);
    }

    // 暂停
    function setStop(bool isStop) external onlyOwner {
        stop = isStop;
        emit StopStatusChanged(stop);
    }

    // 紧急提取
    function emergencyWithdraw(
        address coin,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(
            IERC20(coin).balanceOf(address(this)) >= amount,
            "amount error"
        );
        IERC20(coin).safeTransfer(to, amount);
        emit EmergencyWithdraw(coin, to, amount);
    }

    // 查询用户质押记录总数
    function getStakeCount(address user) public view returns (uint256) {
        return stakes[user].length;
    }

    function getStakesPage(
        address user,
        uint256 startIndex
    )
        public
        view
        returns (
            uint256[] memory ids,
            uint256[] memory amounts,
            uint256[] memory startTimes,
            uint256[] memory unlockTimes,
            uint256[] memory rewards
        )
    {
        uint256 totalCount = getStakeCount(user);
        require(startIndex < totalCount, "Invalid start index");
        uint256 endIndex = startIndex + 10 > totalCount
            ? totalCount - startIndex
            : 10;

        amounts = new uint256[](endIndex);
        startTimes = new uint256[](endIndex);
        unlockTimes = new uint256[](endIndex);
        rewards = new uint256[](endIndex);
        ids = new uint256[](endIndex);

        uint256 tempCumulativeRewardRate = cumulativeRewardRate;
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        if (timeElapsed > 0 && currentRewardPerDay > 0) {
            tempCumulativeRewardRate +=
                (timeElapsed * currentRewardPerDay * 1e18) /
                1 days;
        }

        for (uint256 i = 0; i < endIndex; i++) {
            uint256 stakeIndex = totalCount - 1 - (startIndex + i); // 倒序索引
            ids[i] = stakeIndex;
            amounts[i] = stakes[user][stakeIndex].amount;
            startTimes[i] = stakes[user][stakeIndex].startTime;
            unlockTimes[i] = stakes[user][stakeIndex].unlockTime;
            rewards[i] =
                (stakes[user][stakeIndex].amount *
                    (tempCumulativeRewardRate -
                        stakes[user][stakeIndex].userRewardRate)) /
                1e18 /
                1e18;
        }

        return (ids, amounts, startTimes, unlockTimes, rewards);
    }
}
