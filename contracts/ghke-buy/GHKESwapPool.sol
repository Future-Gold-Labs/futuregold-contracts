// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IGHKBuyPool {
    function buyTo(
        address user,
        address coin,
        uint256 usdtAmount,
        uint256 offchainXAUPrice,
        uint256 deadline,
        bytes calldata sig
    ) external returns (bool);
}

contract GHKESwapPool is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    //chainlink预言机 USDT-USD
    AggregatorV3Interface internal dataFeedUSDT;

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
    //兑换手续费，扩大10000倍
    uint256 public SWAP_GHK_FEE_PERCENTAGE;
    //手续费接收地址
    address public USD_TO_ADDRESS;

    //暂停交易
    bool public stop;

    //黑名单
    mapping(address => bool) private _blacklist;

    event Swap(
        address indexed user, // 购买者
        uint256 amount, // 支付的 GHKE 数量
        uint256 price, // 当时的 GHKE->USDT 价格
        uint256 usdtAmount, // GHKE->USDT->GHK 转换过程中使用的 USDT 数量
        uint256 feePercentage, // 兑换手续费费率
        uint256 fee // 兑换手续费数量
    );
    event AddedToBlacklist(address indexed account);
    event RemovedFromBlacklist(address indexed account);
    event SwapGHKEAmountMinUpdated(uint256 indexed oldValue, uint256 newValue);
    event GHKE_USDT_PriceUpdated(uint256 indexed oldValue, uint256 newValue);
    event SwapGHKFeePercentageUpdated(uint256 indexed oldValue, uint256 newValue);
    event USDToAddressUpdated(address oldTo, address newTo);
    event StopStatusChanged(bool indexed stop);

    event EmergencyWithdraw(address indexed coin, address to, uint256 amount);

    function initialize(
        address _usdToAddress,
        address _GHKE,
        address _USDT,
        address _dataFeedUSDT,
        address _GHK_BUY_POOL_ADDRESS
    ) public initializer {
        __Ownable_init(msg.sender);
        USD_TO_ADDRESS = _usdToAddress;
        GHKE = IERC20(_GHKE);
        USDT = IERC20(_USDT);
        dataFeedUSDT = AggregatorV3Interface(_dataFeedUSDT);
        GHK_BUY_POOL_ADDRESS = _GHK_BUY_POOL_ADDRESS;
        SWAP_GHKE_AMOUNT_MIN = 100 * 1e18;
        GHKE_USDT_PRICE = 1e17; // 0.1
        SWAP_GHK_FEE_PERCENTAGE = 25; // 0.25%

        OZ_TO_G = 311034768000;
    }

    //usdtPrice*1e18
    function getUsdtPrice() public view returns (uint256) {
        (, int256 price, , , ) = dataFeedUSDT.latestRoundData();
        uint256 usdtPrice = (uint256(price) * 1e10); // 价格预言机返回的是 8 位精度，扩大 1e10 变成 18 位精度
        return usdtPrice;
    }

    /// @dev 获取以 USDT 计价的金价，精度 1e10。该方法前端也在调用
    /// @param offchainXAUPrice 链下 XAU 价格，单位 USD/oz，精度 1e18
    /// @return 以 USDT 计价的金价，单位 USDT/g，精度 1e10
    function getPrice(uint256 offchainXAUPrice) public view returns (uint256) {
        // !! 这里不验证 offchainXAUPrice 的可靠性，由 GHKBuyPool.buyTo() 方法验证

        uint256 gPrice = (offchainXAUPrice * 1e10) / OZ_TO_G / 1e8; // OZ_TO_G 有 10 位精度，gPrice 的精度是 1e18/1e8=1e10

        uint256 usdtPrice = getUsdtPrice();
        gPrice = (gPrice * 1e18) / usdtPrice; // 转换成以 USDT 计价的价格。usdtPrice 是 18 位精度，所以返回值是 gPrice 的精度，即 10 位精度
        return gPrice;
    }

    function getAmountOutAndFee(
        uint256 amountIn,
        uint256 offchainXAUPrice
    ) external view returns (uint256 ghkAmount, uint256 fee) {
        // 1/2 GHKE->USDT
        uint256 usdtAmount = (amountIn * GHKE_USDT_PRICE) / 1e18; // 这里取了巧，USDT和USDC都是18位精度，刚好GHKE也是18位精度。因为 usdcPrice 是 18 位精度，所以只需除以 1e18

        uint256 usdtPrice = getUsdtPrice();
        uint256 usdAmount = (usdtAmount * 1e18) / usdtPrice;

        uint256 gPrice = getPrice(offchainXAUPrice);
        // 2/2 USDT->GHK
        ghkAmount = (usdAmount * 1e10) / gPrice; // 这里取了巧，USDT和USDC都是18位精度，刚好GHK也是18位精度。因为 usdcPrice 是 18 位精度，所以只需除以 1e18
        
        // 兑换手续费
        fee = (usdtAmount * SWAP_GHK_FEE_PERCENTAGE) / 10000;
        
        return (ghkAmount, fee);
    }

    //GHKE->USDT->GHK
    function swap(
        uint256 amount,
        uint256 offchainXAUPrice,
        uint256 deadline,
        bytes calldata sig
    ) external {
        require(!stop, "stopped");
        require(!_blacklist[msg.sender], "Blacklist: user is blacklisted");
        require(amount >= SWAP_GHKE_AMOUNT_MIN, "amount less than min");

        // GHKE 价值多少 USDT
        uint256 usdtAmount = (amount * GHKE_USDT_PRICE) / 1e18;

        // 用户需要支付的手续费
        uint256 fee = (usdtAmount * SWAP_GHK_FEE_PERCENTAGE) / 10000;

        // 销毁 GHKE
        (bool success, ) = address(GHKE).call(abi.encodeWithSignature("burnFrom(address,uint256)", msg.sender, amount));
        require(success, "Burn failed");

        // 使用 USDT 购买 GHK
        USDT.approve(GHK_BUY_POOL_ADDRESS, usdtAmount);
        IGHKBuyPool(GHK_BUY_POOL_ADDRESS).buyTo(
            msg.sender,
            address(USDT),
            usdtAmount,
            offchainXAUPrice,
            deadline,
            sig
        );

        // 用户支付手续费
        IERC20(USDT).safeTransferFrom(msg.sender, USD_TO_ADDRESS, fee);

        emit Swap(msg.sender, amount, GHKE_USDT_PRICE, usdtAmount, SWAP_GHK_FEE_PERCENTAGE, fee);
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

    function setDataFeedUSDT(address _dataFeedUSDT) external onlyOwner {
        dataFeedUSDT = AggregatorV3Interface(_dataFeedUSDT);
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

    // 修改兑换手续费
    function setSwapGHKFeePercentage(
        uint256 _newFeePercentage
    ) external onlyOwner {
        require(
            _newFeePercentage <= 10000,
            "Fee percentage cannot exceed 100%"
        );
        uint256 oldValue = SWAP_GHK_FEE_PERCENTAGE;
        SWAP_GHK_FEE_PERCENTAGE = _newFeePercentage;
        emit SwapGHKFeePercentageUpdated(oldValue, _newFeePercentage);
    }

    // 修改手续费接收地址
    function setUsdToAddress(address _usdToAddress) external onlyOwner {
        require(_usdToAddress != address(0), "Invalid address");
        address oldTo = USD_TO_ADDRESS;
        USD_TO_ADDRESS = _usdToAddress;
        emit USDToAddressUpdated(oldTo, _usdToAddress);
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
}
