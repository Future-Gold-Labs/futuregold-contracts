// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract GHKBuyPool is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    //chainlink预言机
    AggregatorV3Interface internal dataFeedXAU;
    AggregatorV3Interface internal dataFeedUSDT;
    AggregatorV3Interface internal dataFeedUSDC;

    address public USDT;
    address public USDC;

    //线上购买最小值，扩大 1e18
    uint256 public BUY_GHK_AMOUNT_MIN;
    //线上购买最大值，扩大 1e18
    uint256 public BUY_GHK_AMOUNT_MAX;
    //购买手续费，扩大10000倍
    uint256 public BUY_GHK_FEE_PERCENTAGE;

    //GHK合约地址
    IERC20 public GHK;
    IERC20 public GHKE;
    address public USD_TO_ADDRESS;
    //金盎司转换克的转换比例，扩大 1e10
    uint256 private OZ_TO_G;

    // 最新的 XAU 出售价格，精度为 18 位
    uint256 public latestXAUPrice;
    // 链下价格和预言机价格的最大偏差比例，精度为 4 位，例如：1% = 100/10000; 0.8% = 80/10000
    uint256 public maxOraclePriceDeviation;
    // 链下价格和最新 XAU 出售价格的最大偏差比例，精度为 4 位，例如：10% = 1000/10000; 5% = 200/10000
    uint256 public maxLatestPriceDeviation;
    // 链下价格的签名地址
    address public signer;

    //交易代币合约地址
    mapping(address => bool) public tradeTokens;
    //邀请人
    mapping(address => bool) public inviterStatus;
    mapping(address => address) public inviters;
    //GHKE->GHK的价格，精度为 8 位
    uint256 public GHK_GHKE_PRICE;
    //一级邀请奖励比例，扩大10000倍
    uint256 public INVITER_REWARD_LEVEL_1;
    //二级邀请奖励比例，扩大10000倍
    uint256 public INVITER_REWARD_LEVEL_2;

    //黑名单
    mapping(address => bool) private _blacklist;

    //GHKE Buy Pool
    address public GHKE_BUY_POOL;

    event BindInviter(address indexed to, address inviter);

    event TokenBuy(
        address indexed to, // 购买者
        address inviter, // 邀请人
        uint256 ghkValue, // 购买的 GHK 数量
        address tradeToken, // 购买使用的交易代币
        uint256 gPrice, // 当时的金价，单位：USD/g，精度 1e10
        uint256 usdValue, // 购买的等值 USD 数量，等于 ghkValue*price
        uint256 feePercentage, // 购买手续费
        uint256 tokenPrice, // 购买使用的交易代币的价格
        uint256 tokenValue // 购买使用的交易代币的数量
    );

    event BuyOffline(address indexed to, uint256 ghkValue);

    event AddedToBlacklist(address indexed account);
    event RemovedFromBlacklist(address indexed account);

    event USDToAddressUpdated(address oldTo, address newTo);

    event BuyGHKAmountMinUpdated(uint256 indexed oldVal, uint256 newVal);
    event BuyGHKAmountMaxUpdated(uint256 indexed oldVal, uint256 newVal);
    event BuyGHKFeePercentageUpdated(uint256 indexed oldVal, uint256 newVal);
    event EmergencyWithdraw(address indexed coin, address to, uint256 amount);
    event InviterReward(
        address indexed user, // 被邀请人
        uint256 level, // 邀请等级
        address inviter, // 邀请人
        uint256 inviterReward, // 邀请人获得的奖励数量
        uint256 ghkAmount, // 被邀请人购买的 GHK 数量
        uint256 rate, // 邀请奖励比例
        uint256 price // GHK/GHKE 价格
    );

    event TradeTokenUpdated(address indexed token, bool enabled);
    event GHK_GHKE_PriceUpdated(uint256 newPrice);
    event InviterRewardLevel1Updated(uint256 rate);
    event InviterRewardLevel2Updated(uint256 rate);

    function initialize(
        address _usdToAddress,
        address _GHK,
        address _GHKE,
        address _USDT,
        address _USDC,
        address _dataFeedXAU,
        address _dataFeedUSDT,
        address _dataFeedUSDC,
        uint256 _initialXAUPrice,
        address _signer
    ) public initializer {
        __Ownable_init(msg.sender);
        GHK = IERC20(_GHK);
        GHKE = IERC20(_GHKE);
        USDT = _USDT;
        USDC = _USDC;
        tradeTokens[_USDT] = true;
        tradeTokens[_USDC] = true;
        dataFeedXAU = AggregatorV3Interface(_dataFeedXAU);
        dataFeedUSDT = AggregatorV3Interface(_dataFeedUSDT);
        dataFeedUSDC = AggregatorV3Interface(_dataFeedUSDC);
        BUY_GHK_AMOUNT_MIN = 10 * 1e18; // 10
        BUY_GHK_AMOUNT_MAX = 5000 * 1e18; // 5000
        BUY_GHK_FEE_PERCENTAGE = 25; // 0.25%
        GHK_GHKE_PRICE = 100 * 1e8; // 100
        INVITER_REWARD_LEVEL_1 = 100; // 1%
        INVITER_REWARD_LEVEL_2 = 50; // 0.5%
        OZ_TO_G = 311034768000;
        USD_TO_ADDRESS = _usdToAddress;
        inviterStatus[_usdToAddress] = true;

        latestXAUPrice = _initialXAUPrice;
        // 链下价格和预言机价格的最大偏差比例，精度为 4 位，例如：1% = 100/10000; 0.8% = 80/10000
        maxOraclePriceDeviation = 80; // 0.8%
        // 链下价格和最新 XAU 出售价格的最大偏差比例，精度为 4 位，例如：10% = 1000/10000; 5% = 200/10000
        maxLatestPriceDeviation = 1000; // 10%
        signer = _signer;
    }

    function _verifySignature(
        address user_wallet,
        uint256 offchainXAUPrice,
        uint256 deadline,
        bytes calldata sig
    ) internal view returns (bool) {
        require(block.timestamp < deadline, "Signature expired");

        bytes32 messageHash = keccak256(
            abi.encodePacked(offchainXAUPrice, deadline, user_wallet)
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );
        address recoveredSigner = ECDSA.recover(ethSignedMessageHash, sig);

        return (recoveredSigner == signer);
    }

    function _checkOffchainXAUPrice(uint256 offchainXAUPrice) internal view {
        (, int256 price, , , ) = dataFeedXAU.latestRoundData();
        // 在 bnb testnet 链上从 oracle 查询到的 XAU 价格精度是 18 位，但在 bnb mainnet 链上只有 8 位
        uint256 oracleXAUPrice = uint256(price); // bnb testnet
        // uint256 oracleXAUPrice = uint256(price * 1e10); // bnb mainnet

        // 验证链下价格的可靠性
        // 1. 链下价格不能偏离预言机价格超过 'maxOraclePriceDeviation/10000'
        // 2. 链下价格不能偏离最新的 XAU 出售价格超过 'maxLatestPriceDeviation/10000'

        require(
            offchainXAUPrice >= oracleXAUPrice ||
                offchainXAUPrice >=
                (oracleXAUPrice * (10000 - maxOraclePriceDeviation)) / 10000,
            "Offchain price deviates from oracle price too much"
        );

        require(
            offchainXAUPrice >= latestXAUPrice ||
                offchainXAUPrice >=
                (latestXAUPrice * (10000 - maxLatestPriceDeviation)) / 10000,
            "Offchain price deviates from latest price too much"
        );
    }

    /// @dev 获取金价，单位 USD/g，精度 1e10。该方法前端也在调用
    /// @param offchainXAUPrice 链下 XAU 价格，单位 USD/oz，精度 1e18
    /// @return 金价，单位 USD/g，精度 1e10
    function getPrice(uint256 offchainXAUPrice) public view returns (uint256) {
        // 验证链下价格的可靠性
        _checkOffchainXAUPrice(offchainXAUPrice);

        uint256 gPrice = (offchainXAUPrice * 1e10) / OZ_TO_G / 1e8; // OZ_TO_G 有 10 位精度，返回值的精度是 1e18/1e8=1e10

        return gPrice;
    }

    //usdcPrice*1e18
    function getUsdcPrice() public view returns (uint256) {
        (, int256 price, , , ) = dataFeedUSDC.latestRoundData();
        uint256 usdcPrice = (uint256(price) * 1e10); // 价格预言机返回的是 8 位精度，扩大 1e10 变成 18 位精度
        return usdcPrice;
    }

    //usdtPrice*1e18
    function getUsdtPrice() public view returns (uint256) {
        (, int256 price, , , ) = dataFeedUSDT.latestRoundData();
        uint256 usdtPrice = (uint256(price) * 1e10); // 价格预言机返回的是 8 位精度，扩大 1e10 变成 18 位精度
        return usdtPrice;
    }

    /// 购买-线上
    /// @param amount 购买的 GHK 数量，精度 18 位
    /// @param tradeToken 购买使用的交易代币地址，目前只支持 USDT 和 USDC
    /// @param inviter 邀请人地址，如果没有邀请人则传入 0 地址
    /// @param offchainXAUPrice 链下 XAU 价格，单位 USD/oz，精度 18 位
    /// @param deadline 签名过期时间戳
    /// @param sig 签名
    function buy(
        uint256 amount,
        address tradeToken,
        address inviter,
        uint256 offchainXAUPrice,
        uint256 deadline,
        bytes calldata sig
    ) external {
        require(!_blacklist[msg.sender], "Blacklist: user is blacklisted");
        if (inviter != address(0)) {
            require(
                inviter != msg.sender && inviterStatus[inviter],
                "Invalid inviter"
            ); //有效邀请人
        }
        require(amount >= BUY_GHK_AMOUNT_MIN, "amount less than min");
        require(amount <= BUY_GHK_AMOUNT_MAX, "amount more than max");
        require(
            amount <= GHK.balanceOf(address(this)),
            "amount exceed balance"
        );
        require(tradeTokens[tradeToken], "Invalid tradeToken");

        // 验证签名
        require(
            _verifySignature(msg.sender, offchainXAUPrice, deadline, sig),
            "Invalid signature"
        );
        // 获取 XAU 价格
        uint256 gPrice = getPrice(offchainXAUPrice);
        require(gPrice > 0, "Invalid gold price");

        uint256 usdAmount = (amount *
            (BUY_GHK_FEE_PERCENTAGE + 10000) *
            gPrice) /
            10000 /
            1e10; // gPrice 是 10 位精度，所以只需除以 1e10。所以 usdAmount 会和 GHK 的精度一样，都是 18 位精度
        require(usdAmount > 0, "Invalid usdAmount");

        address inviter1 = address(0);
        // 检查当前用户是第一次绑定邀请人
        if (inviter != address(0) && inviters[msg.sender] == address(0)) {
            inviters[msg.sender] = inviter;
            emit BindInviter(msg.sender, inviter);

            inviter1 = inviter;
        }

        if (tradeToken == USDC) {
            uint256 usdcPrice = getUsdcPrice();
            require(usdcPrice > 0, "Invalid usdc price");
            uint256 usdcAmount = (usdAmount * 1e18) / usdcPrice; // 这里取了巧，USDT和USDC都是18位精度，刚好GHK也是18位精度。因为 usdcPrice 是 18 位精度，所以只需除以 1e18
            IERC20(tradeToken).safeTransferFrom(
                msg.sender,
                USD_TO_ADDRESS,
                usdcAmount
            );
            emit TokenBuy(
                msg.sender,
                inviter1,
                amount,
                tradeToken,
                gPrice,
                usdAmount,
                BUY_GHK_FEE_PERCENTAGE,
                usdcPrice,
                usdcAmount
            );
        } else if (tradeToken == USDT) {
            uint256 usdtPrice = getUsdtPrice();
            require(usdtPrice > 0, "Invalid usdt price");
            uint256 usdtAmount = (usdAmount * 1e18) / usdtPrice; // 这里取了巧，USDT和USDC都是18位精度，刚好GHK也是18位精度。因为 usdcPrice 是 18 位精度，所以只需除以 1e18
            IERC20(tradeToken).safeTransferFrom(
                msg.sender,
                USD_TO_ADDRESS,
                usdtAmount
            );
            emit TokenBuy(
                msg.sender,
                inviter1,
                amount,
                tradeToken,
                gPrice,
                usdAmount,
                BUY_GHK_FEE_PERCENTAGE,
                usdtPrice,
                usdtAmount
            );
        } else {
            revert("unsupported tradeToken");
        }

        GHK.safeTransfer(msg.sender, amount);

        //多级邀请
        if (inviter1 != address(0)) {
            //一级
            uint256 inviter1Reward = (amount *
                INVITER_REWARD_LEVEL_1 *
                GHK_GHKE_PRICE) /
                10000 /
                1e8;
            if (GHKE.balanceOf(address(this)) >= inviter1Reward) {
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
        }

        inviterStatus[msg.sender] = true;

        // 更新最新的 XAU 出售价格
        latestXAUPrice = offchainXAUPrice;
    }

    function buyTo(
        address user,
        address coin,
        uint256 usdtAmount,
        uint256 offchainXAUPrice,
        uint256 deadline,
        bytes calldata sig
    ) external returns (bool) {
        require(msg.sender == GHKE_BUY_POOL, "permission denied");
        require(!_blacklist[user], "Blacklist: user is blacklisted");
        uint256 usdtPrice = getUsdtPrice();
        uint256 usdAmount = (usdtAmount * 1e18) / usdtPrice;

        // 验证签名
        require(
            _verifySignature(user, offchainXAUPrice, deadline, sig),
            "Invalid signature"
        );
        // 获取 XAU 价格
        uint256 gPrice = getPrice(offchainXAUPrice);
        require(gPrice > 0, "Invalid gold price");

        uint256 amount = (usdAmount * 1e10) / gPrice;
        // require(amount >= BUY_GHK_AMOUNT_MIN, "amount less than min");
        require(amount <= BUY_GHK_AMOUNT_MAX, "amount more than max");
        require(
            amount <= GHK.balanceOf(address(this)),
            "amount exceed balance"
        );

        IERC20(coin).safeTransferFrom(msg.sender, USD_TO_ADDRESS, usdtAmount);
        emit TokenBuy(
            msg.sender,
            address(0),
            amount,
            coin,
            gPrice,
            usdAmount,
            0,
            usdtPrice,
            usdtAmount
        );

        GHK.safeTransfer(user, amount);

        // 更新最新的 XAU 出售价格
        latestXAUPrice = offchainXAUPrice;

        return true;
    }

    //线下购买-只有管理员有权限操作
    function buyOffline(uint256 amount, address to) external onlyOwner {
        require(!_blacklist[to], "Blacklist: to is blacklisted");
        // require(amount >= BUY_GHK_AMOUNT_MIN, "amount less than min");
        require(amount <= BUY_GHK_AMOUNT_MAX, "amount more than max");
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

    function setDataFeedXAU(address _dataFeedXAU) external onlyOwner {
        dataFeedXAU = AggregatorV3Interface(_dataFeedXAU);
    }

    function setDataFeedUSDT(address _dataFeedUSDT) external onlyOwner {
        dataFeedUSDT = AggregatorV3Interface(_dataFeedUSDT);
    }

    function setDataFeedUSDC(address _dataFeedUSDC) external onlyOwner {
        dataFeedUSDC = AggregatorV3Interface(_dataFeedUSDC);
    }

    function setUSDT(address _USDT) external onlyOwner {
        USDT = _USDT;
    }

    function setUSDC(address _USDC) external onlyOwner {
        USDC = _USDC;
    }

    function setUsdToAddress(address _usdToAddress) external onlyOwner {
        require(_usdToAddress != address(0), "Invalid address");
        address oldTo = USD_TO_ADDRESS;
        USD_TO_ADDRESS = _usdToAddress;
        emit USDToAddressUpdated(oldTo, _usdToAddress);
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
     * @dev 修改线上购买最大值
     * @param _newMax 新价格，以 代币精度位
     */
    function setBuyGHKAmountMax(uint256 _newMax) external onlyOwner {
        require(_newMax > 0, "Maximum buy amount must be greater than 0");
        uint256 oldValue = BUY_GHK_AMOUNT_MAX;
        BUY_GHK_AMOUNT_MAX = _newMax;
        emit BuyGHKAmountMaxUpdated(oldValue, _newMax);
    }

    // 修改购买手续费
    function setBuyGHKFeePercentage(
        uint256 _newFeePercentage
    ) external onlyOwner {
        require(
            _newFeePercentage <= 10000,
            "Fee percentage cannot exceed 100%"
        );
        uint256 oldValue = BUY_GHK_FEE_PERCENTAGE;
        BUY_GHK_FEE_PERCENTAGE = _newFeePercentage;
        emit BuyGHKFeePercentageUpdated(oldValue, _newFeePercentage);
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
     * @dev 更新 GHK/GHKE 价格
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

    // 设置最新的 XAU 出售价格，精度为 18 位
    function setLatestXAUPrice(uint256 price) external onlyOwner {
        latestXAUPrice = price;
    }

    // 设置链下价格和预言机价格的最大偏差比例，精度为 4 位，例如：1% = 100/10000; 0.8% = 80/10000
    function setMaxOraclePriceDeviation(uint256 deviation) external onlyOwner {
        maxOraclePriceDeviation = deviation;
    }

    // 链下价格和最新 XAU 出售价格的最大偏差比例，精度为 4 位，例如：10% = 1000/10000; 5% = 200/10000
    function setMaxLatestPriceDeviation(uint256 deviation) external onlyOwner {
        maxLatestPriceDeviation = deviation;
    }

    // 设置签名地址
    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
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
