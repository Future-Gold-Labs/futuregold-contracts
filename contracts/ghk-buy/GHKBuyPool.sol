// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract GHKBuyPool is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    //chainlink预言机
    AggregatorV3Interface internal dataFeed;

    //线上购买最小值 - 0.01g
    uint256 public BUY_GHK_AMOUNT_MIN;

    //GHK合约地址
    IERC20 public GHK;
    IERC20 public GHKE;
    address public USD_TO_ADDRESS;
    //金盎司转换克的转换比例，扩大 1e10
    uint256 private OZ_TO_G;

    //交易代币合约地址
    mapping(address => bool) public tradeTokens;
    //邀请人
    mapping(address => bool) public inviterStatus;
    mapping(address => address) public inviters;
    //GHKE->GHK的价格 10000 = 1GHK=10000GHKE
    uint256 public GHK_GHKE_PRICE;
    //一级邀请奖励比例 1% = 100/10000
    uint256 public INVITER_REWARD_LEVEL_1;
    //二级邀请奖励比例 0.5% = 50/10000
    uint256 public INVITER_REWARD_LEVEL_2;

    //黑名单
    mapping(address => bool) private _blacklist;

    //GHKE Buy Pool
    address public GHKE_BUY_POOL;

    // ============ 事件 ============
    event Buy(
        address indexed to,
        uint256 ghkValue,
        address tradeToken,
        uint256 price,
        uint256 usdValue
    );
    event BuyOffline(address indexed to, uint256 ghkValue);

    event AddedToBlacklist(address indexed account);
    event RemovedFromBlacklist(address indexed account);

    event BuyGHKAmountMinUpdated(uint256 indexed oldVal, uint256 newVal);
    event EmergencyWithdraw(address indexed coin, address to, uint256 amount);
    event InviterReward(
        address indexed user,
        uint256 level,
        address inviter,
        uint256 inviterReward,
        uint256 ghkAmount,
        uint256 rate,
        uint256 price
    );

    event TradeTokenUpdated(address indexed token, bool enabled);
    event GHK_GHKE_PriceUpdated(uint256 newPrice);
    event InviterRewardLevel1Updated(uint256 rate);
    event InviterRewardLevel2Updated(uint256 rate);

    function initialize(
        address _GHK,
        address _GHKE,
        address _USDT,
        address _USDC,
        address _XAU_USD
    ) public initializer {
        __Ownable_init(msg.sender);
        GHK = IERC20(_GHK);
        GHKE = IERC20(_GHKE);
        tradeTokens[_USDT] = true;
        tradeTokens[_USDC] = true;
        dataFeed = AggregatorV3Interface(_XAU_USD);
        BUY_GHK_AMOUNT_MIN = 1 * 1e16;
        GHK_GHKE_PRICE = 10000 * 1e8;
        INVITER_REWARD_LEVEL_1 = 100;
        INVITER_REWARD_LEVEL_2 = 50;
        OZ_TO_G = 311034768000;
        USD_TO_ADDRESS = msg.sender;
        inviterStatus[msg.sender] = true;
    }

    function setDataFeed(address _priceDataFeed) external onlyOwner {
        dataFeed = AggregatorV3Interface(_priceDataFeed);
    }

    function getPrice() public view returns (uint256) {
        (
            ,
            /* uint80 roundID */ int256 price /*uint startedAt*/ /*uint timeStamp*/ /* uint80 answeredInRound */,
            ,
            ,

        ) = dataFeed.latestRoundData();
        uint256 gPrice = (uint256(price) * 1e10) / OZ_TO_G / 1e8;

        return gPrice;

    }

    //购买-线上
    function buy(uint256 amount, address tradeToken, address inviter) external {
        require(!_blacklist[msg.sender], "Blacklist: user is blacklisted");
        if (inviter != address(0)) {
            require(
                inviter != msg.sender && inviterStatus[inviter],
                "Invalid inviter"
            ); //有效邀请人
        }
        require(amount >= BUY_GHK_AMOUNT_MIN, "amount less than min");
        require(
            amount <= GHK.balanceOf(address(this)),
            "amount exceed balance"
        );
        require(tradeTokens[tradeToken], "Invalid tradeToken");

        uint256 gPrice = getPrice();
        require(gPrice > 0, "Invalid gold price");

        uint256 usdAmount = (amount * gPrice) / 1e10;
        require(usdAmount > 0, "Invalid usdAmount");

        if (tradeToken == USDC) {
            uint256 usdcPrice = getUsdcPrice();
            require(usdcPrice > 0, "Invalid usdc price");
            uint256 usdcAmount = (usdAmount * 1e18) / usdcPrice;
            IERC20(tradeToken).safeTransferFrom(
                msg.sender,
                USD_TO_ADDRESS,
                usdcAmount
            );
            emit TokenBuyEvent(
                msg.sender,
                amount,
                tradeToken,
                gPrice,
                usdAmount,
                usdcPrice,
                usdcAmount
            );
        } else if (tradeToken == USDT) {
            uint256 usdtPrice = getUsdtPrice();
            require(usdtPrice > 0, "Invalid usdt price");
            uint256 usdtAmount = (usdAmount * 1e18) / usdtPrice;
            IERC20(tradeToken).safeTransferFrom(
                msg.sender,
                USD_TO_ADDRESS,
                usdtAmount
            );
            emit TokenBuyEvent(
                msg.sender,
                amount,
                tradeToken,
                gPrice,
                usdAmount,
                usdtPrice,
                usdtAmount
            );
        } else {
            IERC20(tradeToken).safeTransferFrom(
                msg.sender,
                USD_TO_ADDRESS,
                usdAmount
            );
        }

        GHK.safeTransfer(msg.sender, amount);
        //多级邀请
        if (inviter != address(0) && inviters[msg.sender] == address(0)) {
            inviters[msg.sender] = inviter;
            emit BindInviter(msg.sender, inviter);
        }
        //一级
        address inviter1 = inviters[msg.sender];
        uint256 inviter1Reward = (amount *
            INVITER_REWARD_LEVEL_1 *
            GHK_GHKE_PRICE) /
            10000 /
            1e8;
        if (
            inviter1 != address(0) &&
            GHKE.balanceOf(address(this)) >= inviter1Reward
        ) {
            GHKE.safeTransfer(inviter1, inviter1Reward);
            emit InviterReward(
                msg.sender,
                1,
                inviter1,
                inviter1Reward,
                amount,
                INVITER_REWARD_LEVEL_1,
                GHK_GHKE_PRICE
            );
        }

        //二级
        address inviter2 = inviters[inviter1];
        uint256 inviter2Reward = (amount *
            INVITER_REWARD_LEVEL_2 *
            GHK_GHKE_PRICE) /
            10000 /
            1e8;
        if (
            inviter2 != address(0) &&
            GHKE.balanceOf(address(this)) >= inviter2Reward
        ) {
            GHKE.safeTransfer(inviter2, inviter2Reward);
            emit InviterReward(
                msg.sender,
                2,
                inviter2,
                inviter2Reward,
                amount,
                INVITER_REWARD_LEVEL_2,
                GHK_GHKE_PRICE
            );
        }

        inviterStatus[msg.sender] = true;
        emit BuyEvent(
            msg.sender,
            inviter1,
            amount,
            tradeToken,
            gPrice,
            usdAmount
        );
    }

    function buyTo(
        address user,
        address coin,
        uint256 usdtAmount
    ) external returns (bool) {
        require(msg.sender == GHKE_BUY_POOL, "permission denied");
        require(!_blacklist[user], "Blacklist: user is blacklisted");
        uint256 usdtPrice = getUsdtPrice();
        uint256 usdAmount = (usdtAmount * 1e18) / usdtPrice;

        uint256 gPrice = getPrice();
        require(gPrice > 0, "Invalid gold price");

        uint256 amount = (usdAmount * 1e10) / gPrice;
        require(amount >= BUY_GHK_AMOUNT_MIN, "amount less than min");
        require(
            amount <= GHK.balanceOf(address(this)),
            "amount exceed balance"
        );

        IERC20(coin).safeTransferFrom(
            msg.sender,
            USD_TO_ADDRESS,
            usdtAmount
        );
        emit TokenBuyEvent(
            msg.sender,
            amount,
            coin,
            gPrice,
            usdAmount,
            usdtPrice,
            usdtAmount
        );

        GHK.safeTransfer(user, amount);

        emit BuyEvent(user, address(0), amount, coin, gPrice, usdAmount);
        return true;
    }

    //线下购买-只有管理员有权限操作
    function buyOffline(uint256 amount, address to) external onlyOwner {
        require(!_blacklist[to], "Blacklist: to is blacklisted");
        require(amount >= BUY_GHK_AMOUNT_MIN, "amount less than min");
        require(
            amount <= GHK.balanceOf(address(this)),
            "amount exceed balance"
        );

        GHK.safeTransfer(to, amount);
        emit BuyOffline(to, amount);
    }

    function addToBlacklist(address account) external onlyOwner {
        require(account != address(0), "BlacklistToken: Zero address");
        require(!_blacklist[account], "BlacklistToken: Already blacklisted");
        _blacklist[account] = true;
        emit AddedToBlacklist(account);
    }

    function removeFromBlacklist(address account) external onlyOwner {
        require(account != address(0), "BlacklistToken: Zero address");
        require(_blacklist[account], "BlacklistToken: Not blacklisted");
        _blacklist[account] = false;
        emit RemovedFromBlacklist(account);
    }

    function isBlacklisted(address account) public view returns (bool) {
        return _blacklist[account];
    }
    /**
     * @dev 修改线上购买最小值
     * @param _newMin 新价格，以 代币精度位
     */
    function setBuyGHKAmountMin(uint256 _newMin) external onlyOwner {
        require(_newMin > 0, "Minimum buy amount must be greater than 0");
        uint256 oldValue = BUY_GHK_AMOUNT_MIN;
        BUY_GHK_AMOUNT_MIN = _newMin;
        emit BuyGHKAmountMinUpdated(oldValue, _newMin);
    }
    /**
     * @dev 设置交易代币是否允许交易
     * @param tokenAddress 代币地址
     * @param enabled 是否启用交易
     */
    function setTradeToken(
        address tokenAddress,
        bool enabled
    ) external onlyOwner {
        tradeTokens[tokenAddress] = enabled;
        emit TradeTokenUpdated(tokenAddress, enabled);
    }

    /**
     * @dev 更新 GHK/GHKE 价格（例如调整为 1 GHK = 12000 GHKE）
     * @param newPrice 新价格，以 1e8 为精度单位
     */
    function setGHK_GHKE_Price(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be greater than 0");
        GHK_GHKE_PRICE = newPrice;
        emit GHK_GHKE_PriceUpdated(newPrice);
    }

    /**
     * @dev 设置一级邀请奖励比例（单位：基点，1% = 100）
     * @param rate 新比例，范围建议 0 ~ 10000（即 0% ~ 100%）
     */
    function setInviterRewardLevel1(uint256 rate) external onlyOwner {
        require(rate <= 10000, "Rate cannot exceed 100%");
        INVITER_REWARD_LEVEL_1 = rate;
        emit InviterRewardLevel1Updated(rate);
    }

    /**
     * @dev 设置二级邀请奖励比例（单位：基点，1% = 100）
     * @param rate 新比例，范围建议 0 ~ 10000（即 0% ~ 100%）
     */
    function setInviterRewardLevel2(uint256 rate) external onlyOwner {
        require(rate <= 10000, "Rate cannot exceed 100%");
        INVITER_REWARD_LEVEL_2 = rate;
        emit InviterRewardLevel2Updated(rate);
    }

    //设置GHKE的购买池子地址，只有该池子能执行buyTo
    function setGHKE_BUY_POOL(address pool) external onlyOwner {
        GHKE_BUY_POOL = pool;
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

    event BuyEvent(
        address indexed to,
        address inviter,
        uint256 ghkValue,
        address tradeToken,
        uint256 price,
        uint256 usdValue
    );

    event BindInviter(address indexed to, address inviter);

    event TokenBuyEvent(
        address indexed to,
        uint256 ghkValue,
        address tradeToken,
        uint256 gPrice,
        uint256 usdValue,
        uint256 tokenPrice,
        uint256 tokenValue
    );

    //chainlink预言机 USDC-USD
    AggregatorV3Interface internal dataFeedUSDC_USD;

    function setDataFeedUSDC_USD(address _priceDataFeed) external onlyOwner {
        dataFeedUSDC_USD = AggregatorV3Interface(_priceDataFeed);
    }

    //usdcPrice*1e18
    function getUsdcPrice() public view returns (uint256) {
        (
            ,
            /* uint80 roundID */ int256 price /*uint startedAt*/ /*uint timeStamp*/ /* uint80 answeredInRound */,
            ,
            ,

        ) = dataFeedUSDC_USD.latestRoundData();
        uint256 usdcPrice = (uint256(price) * 1e10);
        return usdcPrice;
    }

    address public USDC;
    function setUSDC(address _USDC) external onlyOwner {
        USDC = _USDC;
    }

    //chainlink预言机 USDT-USD
    AggregatorV3Interface internal dataFeedUSDT_USD;

    function setDataFeedUSDT_USD(address _priceDataFeed) external onlyOwner {
        dataFeedUSDT_USD = AggregatorV3Interface(_priceDataFeed);
    }

    //usdtPrice*1e18
    function getUsdtPrice() public view returns (uint256) {
        (
            ,
            /* uint80 roundID */ int256 price /*uint startedAt*/ /*uint timeStamp*/ /* uint80 answeredInRound */,
            ,
            ,

        ) = dataFeedUSDT_USD.latestRoundData();
        uint256 usdtPrice = (uint256(price) * 1e10);
        return usdtPrice;
    }

    address public USDT;
    function setUSDT(address _USDT) external onlyOwner {
        USDT = _USDT;
    }
}
