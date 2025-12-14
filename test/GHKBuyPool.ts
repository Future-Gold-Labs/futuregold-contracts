import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";

import { getOffchainXAUPrice, sign, sign_with_privateKey } from "./helper.js";
import { getContract, parseAbi, parseEther, parseUnits } from "viem";

describe("GHKBuyPool", async () => {
  const { viem, networkHelpers } = await network.connect();
  const [walletClient] = await viem.getWalletClients();

  const USDT_ADDR =
    "0x55d398326f99059ff775485246999027b3197955" as `0x${string}`;
  const USDC_ADDR =
    "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d" as `0x${string}`;

  const USDT_DECIMALS = 18;
  const USDC_DECIMALS = 18;

  const DATAFEEDS_XAU_USD =
    "0x86896fEB19D8A607c3b11f2aF50A0f239Bd71CD0" as `0x${string}`;
  const DATAFEEDS_USDT_USD =
    "0xB97Ad0E74fa7d920791E90258A6E2085088b4320" as `0x${string}`;
  const DATAFEEDS_USDC_USD =
    "0x51597f405303C4377E36123cBc172b13269EA163" as `0x${string}`;

  const userWallet = walletClient.account.address;

  const USDT_WHALE =
    "0x092FE28430BaDe62C7C044B9C77d0aaa06241319" as `0x${string}`;

  const BUY_GHK_AMOUNT = parseUnits("1", 18); // 1 GHK
  const INVITER_ADDR =
    "0x0000000000000000000000000000000000000000" as `0x${string}`;

  async function deployContractsFixture() {
    const USDT = getContract({
      address: USDT_ADDR,
      abi: parseAbi([
        "function approve(address spender, uint256 value) returns (bool)",
        "function transfer(address to, uint256 value) returns (bool)",
        "function balanceOf(address account) view returns (uint256)",
        "function decimals() view returns (uint8)",
      ]),
      client: walletClient,
    });
    const USDC = getContract({
      address: USDC_ADDR,
      abi: USDT.abi,
      client: walletClient,
    });

    // const usdtDecimals = await USDT.read.decimals();
    // const usdcDecimals = await USDC.read.decimals();
    // console.log("USDT decimals:", usdtDecimals);
    // console.log("USDC decimals:", usdcDecimals);

    const GHK = await viem.deployContract("GHKToken");
    await GHK.write.initialize([10_000n]);

    const GHKE = await viem.deployContract("GHKEToken");
    await GHKE.write.initialize();

    const GHKBuyPool = await viem.deployContract("GHKBuyPool");
    await GHKBuyPool.write.initialize([
      GHK.address,
      GHKE.address,
      USDT.address,
      USDC.address,
      DATAFEEDS_XAU_USD,
      DATAFEEDS_USDT_USD,
      DATAFEEDS_USDC_USD,
      4202_242759559214530560n,
      // 3202_242759559214530560n,
      userWallet,
    ]);
    // await GHKBuyPool.write.setUSDT([USDT.address]);
    // await GHKBuyPool.write.setUSDC([USDC.address]);

    // await GHKBuyPool.write.setDataFeedUSDT_USD([DATAFEEDS_USDT_USD]);
    // await GHKBuyPool.write.setDataFeedUSDC_USD([DATAFEEDS_USDC_USD]);

    // 将 GHK 转入 GHKBuyPool 合约
    await GHK.write.transfer([GHKBuyPool.address, 10_000n * 10n ** 18n]);
    // 将 GHKE 转入 GHKBuyPool 合约
    await GHKE.write.transfer([
      GHKBuyPool.address,
      1_000_000_000n * 10n ** 18n,
    ]);
    // 从鲸鱼账号给用户转 USDT USDC
    await networkHelpers.impersonateAccount(USDT_WHALE);
    await networkHelpers.setBalance(USDT_WHALE, parseEther("1"));
    await USDT.write.transfer(
      [userWallet, parseUnits("10000", USDT_DECIMALS)],
      {
        account: USDT_WHALE,
      }
    );

    {
      const GHK_GHKBuyPoolBalance = await GHK.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const GHK_UserBalance = await GHK.read.balanceOf([userWallet]);

      const GHKE_GHKBuyPoolBalance = await GHKE.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const GHKE_UserBalance = await GHKE.read.balanceOf([userWallet]);

      const USDT_GHKBuyPoolBalance = await USDT.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const USDT_UserBalance = await USDT.read.balanceOf([userWallet]);

      const USDC_GHKBuyPoolBalance = await USDC.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const USDC_UserBalance = await USDC.read.balanceOf([userWallet]);

      console.log("初始状态：");
      console.log(" GHK-GHKBuyPool:", GHK_GHKBuyPoolBalance);
      console.log(" GHK-User:", GHK_UserBalance);
      console.log(" GHKE-GHKBuyPool:", GHKE_GHKBuyPoolBalance);
      console.log(" GHKE-User:", GHKE_UserBalance);
      console.log(" USDT-GHKBuyPool:", USDT_GHKBuyPoolBalance);
      console.log(" USDT-User:", USDT_UserBalance);
      console.log(" USDC-GHKBuyPool:", USDC_GHKBuyPoolBalance);
      console.log(" USDC-User:", USDC_UserBalance);
    }

    return { GHK, GHKE, USDT, USDC, GHKBuyPool };
  }

  it("buy__签名钱包不匹配", async () => {
    const { GHK, GHKE, USDT, USDC, GHKBuyPool } =
      await networkHelpers.loadFixture(deployContractsFixture);

    const offchainPriceData = await getOffchainXAUPrice();
    console.log("Offchain XAU price data:", offchainPriceData);

    const offchainPrice = BigInt(offchainPriceData.ask * 1e18); // chainlink 预言机的价格精度都是 8 位，但在链上都处理成了 18 位所以这里要乘以 1e18 转换为 18 位精度
    const deadline = BigInt(offchainPriceData.timestamp + 30);
    const sig = await sign_with_privateKey(offchainPrice, deadline, userWallet);

    await viem.assertions.revertWith(
      GHKBuyPool.write.buy([
        BUY_GHK_AMOUNT,
        USDT.address,
        INVITER_ADDR,
        offchainPrice,
        deadline,
        sig,
      ]),
      "Invalid signature"
    );
  });

  it("buy__签名过期", async () => {
    const { GHK, GHKE, USDT, USDC, GHKBuyPool } =
      await networkHelpers.loadFixture(deployContractsFixture);

    const offchainPriceData = await getOffchainXAUPrice();
    console.log("Offchain XAU price data:", offchainPriceData);

    const offchainPrice = BigInt(offchainPriceData.ask * 1e18); // chainlink 预言机的价格精度都是 8 位，但在链上都处理成了 18 位所以这里要乘以 1e18 转换为 18 位精度
    const deadline = 1733831583n; // BigInt(offchainPriceData.timestamp - 300); // 模拟签名过期
    const sig = await sign(walletClient, offchainPrice, deadline, userWallet);

    await viem.assertions.revertWith(
      GHKBuyPool.write.buy([
        BUY_GHK_AMOUNT,
        USDT.address,
        INVITER_ADDR,
        offchainPrice,
        deadline,
        sig,
      ]),
      "Signature expired"
    );
  });

  it("buy__签名包含的价格和实际价格不一致", async () => {
    const { GHK, GHKE, USDT, USDC, GHKBuyPool } =
      await networkHelpers.loadFixture(deployContractsFixture);

    const offchainPriceData = await getOffchainXAUPrice();
    console.log("Offchain XAU price data:", offchainPriceData);

    const offchainPrice = BigInt(offchainPriceData.ask * 1e18); // chainlink 预言机的价格精度都是 8 位，但在链上都处理成了 18 位所以这里要乘以 1e18 转换为 18 位精度
    const deadline = BigInt(offchainPriceData.timestamp + 30);
    const sig = await sign(walletClient, offchainPrice, deadline, userWallet);

    await viem.assertions.revertWith(
      GHKBuyPool.write.buy([
        BUY_GHK_AMOUNT,
        USDT.address,
        INVITER_ADDR,
        3202_242759559214530560n,
        deadline,
        sig,
      ]),
      "Invalid signature"
    );
  });

  it("buy__链下价格和链上预言机价格偏差过大", async () => {
    const { GHK, GHKE, USDT, USDC, GHKBuyPool } =
      await networkHelpers.loadFixture(deployContractsFixture);

    const offchainPriceData = await getOffchainXAUPrice();
    console.log("Offchain XAU price data:", offchainPriceData);

    const offchainPrice = BigInt((offchainPriceData.ask - 1000) * 1e18); // 模拟链下价格过低
    const deadline = BigInt(offchainPriceData.timestamp + 30);
    const sig = await sign(walletClient, offchainPrice, deadline, userWallet);

    await viem.assertions.revertWith(
      GHKBuyPool.write.buy([
        BUY_GHK_AMOUNT,
        USDT.address,
        INVITER_ADDR,
        offchainPrice,
        deadline,
        sig,
      ]),
      "Offchain price deviates from oracle price too much"
    );
  });

  it("buy__链下价格和最新出售价偏差过大", async () => {
    const { GHK, GHKE, USDT, USDC, GHKBuyPool } =
      await networkHelpers.loadFixture(deployContractsFixture);

    const offchainPriceData = await getOffchainXAUPrice();
    console.log("Offchain XAU price data:", offchainPriceData);

    const offchainPrice = BigInt(offchainPriceData.ask * 1e18);
    const deadline = BigInt(offchainPriceData.timestamp + 30);
    const sig = await sign(walletClient, offchainPrice, deadline, userWallet);

    // 修改最新出售价，模拟XAU价格大幅下跌
    await GHKBuyPool.write.setLatestXAUPrice([5202_242759559214530560n]);

    await viem.assertions.revertWith(
      GHKBuyPool.write.buy([
        BUY_GHK_AMOUNT,
        USDT.address,
        INVITER_ADDR,
        offchainPrice,
        deadline,
        sig,
      ]),
      "Offchain price deviates from latest price too much"
    );
  });

  it("buy", async () => {
    const { GHK, GHKE, USDT, USDC, GHKBuyPool } =
      await networkHelpers.loadFixture(deployContractsFixture);

    const offchainPriceData = await getOffchainXAUPrice();
    console.log("Offchain XAU price data:", offchainPriceData);
    const offchainPrice = BigInt(offchainPriceData.ask * 1e18); // chainlink 预言机的价格精度都是 8 位，但在链上都处理成了 18 位所以这里要乘以 1e18 转换为 18 位精度
    const deadline = BigInt(offchainPriceData.timestamp + 30);
    const sig = await sign(walletClient, offchainPrice, deadline, userWallet);
    // console.log(
    //   "offchainPrice:",
    //   offchainPrice.toString(),
    //   "deadline:",
    //   deadline.toString(),
    //   "userWallet:",
    //   userWallet,
    //   "sig:",
    //   sig
    // );

    const usdtPrice = await GHKBuyPool.read.getUsdtPrice();
    console.log("USDT price:", usdtPrice.toString());

    const usdcPrice = await GHKBuyPool.read.getUsdcPrice();
    console.log("USDC price:", usdcPrice.toString());

    const gXAUPrice = await GHKBuyPool.read.getPrice([offchainPrice]);
    console.log("XAU/g price:", gXAUPrice.toString());

    await USDT.write.approve([
      GHKBuyPool.address,
      parseUnits("10000", USDT_DECIMALS),
    ]);
    await GHKBuyPool.write.buy([
      BUY_GHK_AMOUNT,
      USDT.address,
      INVITER_ADDR,
      offchainPrice,
      deadline,
      sig,
    ]);
    
    {
      const GHK_GHKBuyPoolBalance = await GHK.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const GHK_UserBalance = await GHK.read.balanceOf([userWallet]);

      const GHKE_GHKBuyPoolBalance = await GHKE.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const GHKE_UserBalance = await GHKE.read.balanceOf([userWallet]);

      const USDT_GHKBuyPoolBalance = await USDT.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const USDT_UserBalance = await USDT.read.balanceOf([userWallet]);

      const USDC_GHKBuyPoolBalance = await USDC.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const USDC_UserBalance = await USDC.read.balanceOf([userWallet]);

      console.log("购买 GHK 后的状态：");
      console.log(" GHK-GHKBuyPool:", GHK_GHKBuyPoolBalance);
      console.log(" GHK-User:", GHK_UserBalance);
      console.log(" GHKE-GHKBuyPool:", GHKE_GHKBuyPoolBalance);
      console.log(" GHKE-User:", GHKE_UserBalance);
      console.log(" USDT-GHKBuyPool:", USDT_GHKBuyPoolBalance);
      console.log(" USDT-User:", USDT_UserBalance);
      console.log(" USDC-GHKBuyPool:", USDC_GHKBuyPoolBalance);
      console.log(" USDC-User:", USDC_UserBalance);
    }
  });
});
