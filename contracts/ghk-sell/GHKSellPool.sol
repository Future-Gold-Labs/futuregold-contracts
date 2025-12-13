// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract GHKSellPool is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    //chainlink预言机
    AggregatorV3Interface internal dataFeed;

    //线上赎回最小值 - 0.01g
    uint256 public SELL_GHK_AMOUNT_MIN;
    //线上赎回最大值->超过的需要转人工赎回
    uint256 public SELL_GHK_AMOUNT_MAX;

    //实物黄金赎回最小值 - 10g
    uint256 public SELL_OFFLINE_GHK_AMOUNT_MIN;
    //实物黄金最大值 - 1000000g
    uint256 public SELL_OFFLINE_GHK_AMOUNT_MAX;

    //线上赎回手续费 - 扩大10000倍
    uint256 public SELL_GHK_FEE_PERCENTAGE;
    //实物黄金赎回手续费 - 扩大10000倍
    uint256 public SELL_OFFLINE_GHK_FEE_PERCENTAGE;

    //GHK合约地址
    IERC20 public GHK;
    //金盎司转换克的转换比例，扩大 1e10
    uint256 private OZ_TO_G;

    // 最新的 XAU 出售价格，和 AggregatorV3Interface 预言机返回的价格同样精度为 18 位
    uint256 public latestXAUPrice;
    // 链下价格和预言机价格的最大偏差比例，1% = 100/10000; 0.5% = 50/10000
    uint256 public maxOraclePriceDeviation = 50;
    // 链下价格和最新 XAU 出售价格的最大偏差比例，10% = 1000/10000; 2% = 200/10000
    uint256 public maxLatestPriceDeviation = 200;
    // 链下价格的签名地址
    address public signer;

    //交易代币合约地址
    mapping(address => bool) public tradeTokens;
    //黑名单
    mapping(address => bool) private _blacklist;

    // event Buy(
    //     address indexed to,
    //     uint256 ghkValue,
    //     address tradeToken,
    //     uint256 price,
    //     uint256 usdValue
    // );
    // event BuyOffline(address indexed to, uint256 ghkValue);

    event Sell(
        address indexed from, // 赎回用户
        uint256 ghkValue, // 赎回的 GHK 数量
        address tradeToken, // 赎回目标代币，USDT
        uint256 price, // 当时的金价，单位 USDT/g，精度 1e10
        uint256 usdValue, // 赎回得到的 USDT 数量
        uint256 feePercentage // 线上赎回手续费，精度 1e4
    );
    event SellByAdmin(
        address indexed from, // 赎回用户
        uint256 ghkValue, // 赎回的 GHK 数量
        address tradeToken, // 赎回目标代币，USDT
        uint256 price, // 当时的金价，单位 USDT/g，精度 1e10
        uint256 usdValue, // 赎回得到的 USDT 数量
        uint256 feePercentage // 线上赎回手续费，精度 1e4
    );
    event SellOffline(
        address indexed from, // 赎回用户
        uint256 ghkValue, // 赎回的 GHK 数量
        uint256 feePercentage // 实物黄金赎回手续费，精度 1e4
    );

    event AddedToBlacklist(address indexed account);
    event RemovedFromBlacklist(address indexed account);

    event SellGHKAmountMinUpdated(uint256 indexed oldVal, uint256 newVal);
    event SellGHKAmountMaxUpdated(uint256 indexed oldVal, uint256 newVal);
    event SellOfflineGHKAmountMinUpdated(
        uint256 indexed oldVal,
        uint256 newVal
    );
    event SellOfflineGHKAmountMaxUpdated(
        uint256 indexed oldVal,
        uint256 newVal
    );
    event SellGHKFeePercentageUpdated(uint256 indexed oldVal, uint256 newVal);
    event SellOfflineGHKFeePercentageUpdated(
        uint256 indexed oldVal,
        uint256 newVal
    );

    function initialize(
        address _GHK,
        address _USDT,
        address _XAU_USD,
        uint256 _initialXAUPrice,
        address _signer
    ) public initializer {
        __Ownable_init(msg.sender);
        GHK = IERC20(_GHK);
        tradeTokens[_USDT] = true;
        dataFeed = AggregatorV3Interface(_XAU_USD);
        OZ_TO_G = 311034768000;
        //线上赎回最小值 - 0.01g
        SELL_GHK_AMOUNT_MIN = 1 * 1e16;
        //线上赎回最大值->超过的需要转人工赎回
        SELL_GHK_AMOUNT_MAX = 2 * 1e18;

        //实物黄金赎回最小值 - 10g
        SELL_OFFLINE_GHK_AMOUNT_MIN = 10 * 1e18;
        //实物黄金最大值 - 1000000g
        SELL_OFFLINE_GHK_AMOUNT_MAX = 1000000 * 1e18;

        //线上赎回手续费 - 扩大10000倍
        SELL_GHK_FEE_PERCENTAGE = 100;
        //实物黄金赎回手续费 - 扩大10000倍
        SELL_OFFLINE_GHK_FEE_PERCENTAGE = 200;

        latestXAUPrice = _initialXAUPrice;
        signer = _signer;
    }

    function setDataFeed(address _priceDataFeed) external onlyOwner {
        dataFeed = AggregatorV3Interface(_priceDataFeed);
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
        (, int256 price, , , ) = dataFeed.latestRoundData();
        // uint256 oracleXAUPrice = uint256(price); // bnb testnet
        uint256 oracleXAUPrice = uint256(price * 1e10); // bnb mainnet

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

        console.log(
            "offchainXAUPrice=%s oracleXAUPrice=%s latestXAUPrice=%s",
            offchainXAUPrice,
            oracleXAUPrice,
            latestXAUPrice
        );
    }

    function getPrice(uint256 offchainXAUPrice) public view returns (uint256) {
        // (
        //     ,
        //     /* uint80 roundID */ int256 price /*uint startedAt*/ /*uint timeStamp*/ /* uint80 answeredInRound */,
        //     ,
        //     ,
        //
        // ) = dataFeed.latestRoundData();

        // 验证链下价格的可靠性
        _checkOffchainXAUPrice(offchainXAUPrice);

        // uint256 gPrice = (uint256(price) * 1e10) / OZ_TO_G / 1e8;
        uint256 gPrice = (offchainXAUPrice * 1e10) / OZ_TO_G / 1e8; // OZ_TO_G 有 10 位精度，返回值的精度是 1e18/1e8=1e10

        uint256 usdtPrice = getUsdtPrice();
        gPrice = (gPrice * 1e18) / usdtPrice;

        return gPrice;
    }

    //卖出赎回-线上
    function sell(
        uint256 amount,
        address tradeToken,
        uint256 offchainXAUPrice,
        uint256 deadline,
        bytes calldata sig
    ) external {
        require(!_blacklist[msg.sender], "Blacklist: user is blacklisted");
        require(tradeTokens[tradeToken], "Invalid tradeToken");
        require(amount >= SELL_GHK_AMOUNT_MIN, "amount error");

        // 验证签名
        require(
            _verifySignature(msg.sender, offchainXAUPrice, deadline, sig),
            "Invalid signature"
        );
        // 获取 XAU 价格
        uint256 gPrice = getPrice(offchainXAUPrice);
        require(gPrice > 0, "Invalid gold price");
        uint256 usdAmount = (amount * gPrice) / 1e10;
        require(usdAmount > 0, "Invalid usdAmount");
        //fee
        usdAmount = (usdAmount * (10000 - SELL_GHK_FEE_PERCENTAGE)) / 10000;

        GHK.safeTransferFrom(msg.sender, address(this), amount);
        (bool success, ) = address(GHK).call(
            abi.encodeWithSelector(bytes4(keccak256("burn(uint256)")), amount)
        );
        require(success, "Burn failed");

        if (amount <= SELL_GHK_AMOUNT_MAX) {
            IERC20(tradeToken).safeTransfer(msg.sender, usdAmount);
            emit Sell(
                msg.sender,
                amount,
                tradeToken,
                gPrice,
                usdAmount,
                SELL_GHK_FEE_PERCENTAGE
            );
        } else {
            //转人工赎回
            emit SellByAdmin(
                msg.sender,
                amount,
                tradeToken,
                gPrice,
                usdAmount,
                SELL_GHK_FEE_PERCENTAGE
            );
        }

        // 更新最新的 XAU 出售价格
        latestXAUPrice = offchainXAUPrice;
    }

    //线下赎回->合约只销毁
    function sellOffline(uint256 amount) external {
        require(!_blacklist[msg.sender], "Blacklist: user is blacklisted");
        require(
            amount >= SELL_OFFLINE_GHK_AMOUNT_MIN &&
                amount <= SELL_OFFLINE_GHK_AMOUNT_MAX,
            "amount error"
        );
        //销毁GHK
        GHK.safeTransferFrom(msg.sender, address(this), amount);
        (bool success, ) = address(GHK).call(
            abi.encodeWithSelector(bytes4(keccak256("burn(uint256)")), amount)
        );
        require(success, "Burn failed");
        emit SellOffline(msg.sender, amount, SELL_OFFLINE_GHK_FEE_PERCENTAGE);
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

    // 修改线上赎回最小值
    function setSellGHKAmountMin(uint256 _newMin) external onlyOwner {
        require(_newMin > 0, "Minimum sell amount must be greater than 0");
        require(
            _newMin <= SELL_GHK_AMOUNT_MAX,
            "Minimum sell amount must not exceed maximum"
        );
        uint256 oldValue = SELL_GHK_AMOUNT_MIN;
        SELL_GHK_AMOUNT_MIN = _newMin;
        emit SellGHKAmountMinUpdated(oldValue, _newMin);
    }

    // 修改线上赎回最大值
    function setSellGHKAmountMax(uint256 _newMax) external onlyOwner {
        require(
            _newMax >= SELL_GHK_AMOUNT_MIN,
            "Maximum sell amount must not be less than minimum"
        );
        uint256 oldValue = SELL_GHK_AMOUNT_MAX;
        SELL_GHK_AMOUNT_MAX = _newMax;
        emit SellGHKAmountMaxUpdated(oldValue, _newMax);
    }

    // 修改线下赎回最小值
    function setSellOfflineGHKAmountMin(uint256 _newMin) external onlyOwner {
        require(
            _newMin > 0,
            "Minimum offline sell amount must be greater than 0"
        );
        require(
            _newMin <= SELL_OFFLINE_GHK_AMOUNT_MAX,
            "Minimum offline sell amount must not exceed maximum"
        );
        uint256 oldValue = SELL_OFFLINE_GHK_AMOUNT_MIN;
        SELL_OFFLINE_GHK_AMOUNT_MIN = _newMin;
        emit SellOfflineGHKAmountMinUpdated(oldValue, _newMin);
    }

    // 修改线下赎回最大值
    function setSellOfflineGHKAmountMax(uint256 _newMax) external onlyOwner {
        require(
            _newMax >= SELL_OFFLINE_GHK_AMOUNT_MIN,
            "Maximum offline sell amount must not be less than minimum"
        );
        uint256 oldValue = SELL_OFFLINE_GHK_AMOUNT_MAX;
        SELL_OFFLINE_GHK_AMOUNT_MAX = _newMax;
        emit SellOfflineGHKAmountMaxUpdated(oldValue, _newMax);
    }

    // 修改线上赎回手续费
    function setSellGHKFeePercentage(
        uint256 _newFeePercentage
    ) external onlyOwner {
        require(
            _newFeePercentage <= 10000,
            "Fee percentage cannot exceed 100%"
        );
        uint256 oldValue = SELL_GHK_FEE_PERCENTAGE;
        SELL_GHK_FEE_PERCENTAGE = _newFeePercentage;
        emit SellGHKFeePercentageUpdated(oldValue, _newFeePercentage);
    }

    // 修改线下赎回手续费
    function setSellOfflineGHKFeePercentage(
        uint256 _newFeePercentage
    ) external onlyOwner {
        require(
            _newFeePercentage <= 10000,
            "Fee percentage cannot exceed 100%"
        );
        uint256 oldValue = SELL_OFFLINE_GHK_FEE_PERCENTAGE;
        SELL_OFFLINE_GHK_FEE_PERCENTAGE = _newFeePercentage;
        emit SellOfflineGHKFeePercentageUpdated(oldValue, _newFeePercentage);
    }

    // 设置最新的 XAU 出售价格，精度为 18 位
    function setLatestXAUPrice(uint256 price) external onlyOwner {
        latestXAUPrice = price;
    }

    // 设置
    function setMaxOraclePriceDeviation(uint256 deviation) external onlyOwner {
        maxOraclePriceDeviation = deviation;
    }

    // 设置链下价格和最新 XAU 出售价格的最大偏差比例，分母是 10000，10% = 1000/10000 就传入 1000，2% = 200/10000 就传入 200
    function setMaxLatestPriceDeviation(uint256 deviation) external onlyOwner {
        maxLatestPriceDeviation = deviation;
    }

    // 设置签名地址
    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
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
        uint256 usdtPrice = (uint256(price) * 1e10); // 价格预言机返回的是 8 位精度，扩大 1e10 变成 18 位精度
        return usdtPrice;
    }

    address public USDT;

    function setUSDT(address _USDT) external onlyOwner {
        USDT = _USDT;
    }

    // event TokenSellEvent(
    //     address indexed to,
    //     uint256 ghkValue,
    //     address tradeToken,
    //     uint256 gPrice,
    //     uint256 usdValue,
    //     uint256 tokenPrice,
    //     uint256 tokenValue
    // );
}
