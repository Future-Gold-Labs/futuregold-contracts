// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IGHKBuyPool {
    function buyTo(
        address user,
        address coin,
        uint256 usdAmount
    ) external returns (bool);
}

contract GHKESwapPool is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    //chainlink预言机
    AggregatorV3Interface internal dataFeed;

    //最小兑换GHKE的数量
    uint256 public SWAP_GHKE_AMOUNT_MIN;

    //GHKE合约地址
    IERC20 public GHKE;
    //USDT合约地址
    IERC20 public USDT;
    //金盎司转换克的转换比例，扩大 1e10
    uint256 private OZ_TO_G;
    //GHK购买合约地址
    address public GHK_BUY_POOL_ADDRESS;
    //GHKE->USDT的价格 扩大1e18  1u/GHKE =  1GHKE=1e18 USDT
    uint256 public GHKE_USDT_PRICE;

    //暂停交易
    bool public stop;

    //黑名单
    mapping(address => bool) private _blacklist;

    // ============ 事件 ============
    event Swap(
        address indexed user,
        uint256 amount,
        uint256 price,
        uint256 usdAmount
    );
    event AddedToBlacklist(address indexed account);
    event RemovedFromBlacklist(address indexed account);
    event SwapGHKEAmountMinUpdated(uint256 indexed oldValue, uint256 newValue);
    event GHKE_USDT_PriceUpdated(uint256 indexed oldValue, uint256 newValue);
    event StopStatusChanged(bool indexed stop);

    event EmergencyWithdraw(address indexed coin, address to, uint256 amount);

    function initialize(
        address _GHKE,
        address _USDT,
        address _XAU_USD,
        address _GHK_BUY_POOL_ADDRESS
    ) public initializer {
        __Ownable_init(msg.sender);
        GHKE = IERC20(_GHKE);
        USDT = IERC20(_USDT);
        dataFeed = AggregatorV3Interface(_XAU_USD);
        GHK_BUY_POOL_ADDRESS = _GHK_BUY_POOL_ADDRESS;
        SWAP_GHKE_AMOUNT_MIN = 100 * 1e18;
        GHKE_USDT_PRICE = 2 * 1e17;

        OZ_TO_G = 311034768000;
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
        uint256 usdtPrice = getUsdtPrice();
        gPrice = (gPrice * 1e18) / usdtPrice;
        return gPrice;
    }

    function getAmountOut(uint256 amountIn) public view returns (uint256) {
        uint256 usdtAmount = (amountIn * GHKE_USDT_PRICE) / 1e18;

        uint256 usdtPrice = getUsdtPrice();
        uint256 usdAmount = (usdtAmount * 1e18) / usdtPrice;

        uint256 gPrice = getPrice();
        uint256 ghkAmount = (usdAmount * 1e10) / gPrice;
        return ghkAmount;
    }

    //GHKE->USDT->GHK
    function swap(uint256 amount) external {
        require(!stop, "stopped");
        require(!_blacklist[msg.sender], "Blacklist: user is blacklisted");
        require(amount >= SWAP_GHKE_AMOUNT_MIN, "amount less than min");

        uint256 usdAmount = (amount * GHKE_USDT_PRICE) / 1e18;

        GHKE.safeTransferFrom(
            msg.sender,
            0x000000000000000000000000000000000000dEaD,
            amount
        );

        USDT.approve(GHK_BUY_POOL_ADDRESS, usdAmount);
        IGHKBuyPool(GHK_BUY_POOL_ADDRESS).buyTo(
            msg.sender,
            address(USDT),
            usdAmount
        );
        emit Swap(msg.sender, amount, GHKE_USDT_PRICE, usdAmount);
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
     * @dev 更新兑换时GHKE最小值
     * @param _newMin 最新的最小值，以代币精度位 1e18 为精度单位
     */
    function setSwapGHKEAmountMin(uint256 _newMin) external onlyOwner {
        require(_newMin > 0, "Minimum buy amount must be greater than 0");
        uint256 oldValue = SWAP_GHKE_AMOUNT_MIN;
        SWAP_GHKE_AMOUNT_MIN = _newMin;
        emit SwapGHKEAmountMinUpdated(oldValue, _newMin);
    }

    /**
     * @dev GHKE->USDT的价格 扩大1e18  1u/GHKE =  1GHKE=1e18 USDT
     * @param newPrice 新价格，以 1e18 为精度单位
     */
    function setGHKE_USDT_Price(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be greater than 0");
        uint256 oldValue = GHKE_USDT_PRICE;
        GHKE_USDT_PRICE = newPrice;
        emit GHKE_USDT_PriceUpdated(oldValue, newPrice);
    }

    //暂停
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
}
