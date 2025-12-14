import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";

import { getOffchainXAUPrice, sign, sign_with_privateKey } from "./helper.js";
import { getContract, parseAbi, parseEther, parseUnits } from "viem";

describe("GHKESwapPool", async () => {
  const { viem, networkHelpers } = await network.connect();
  const [walletClient] = await viem.getWalletClients();

  const USDT_ADDR =
    "0x55d398326f99059ff775485246999027b3197955" as `0x${string}`;
  const USDC_ADDR =
    "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d" as `0x${string}`;

  const USDT_DECIMALS = 18;
  const USDC_DECIMALS = 18;
  const GHKE_DECIMALS = 18;

  const DATAFEEDS_XAU_USD =
    "0x86896fEB19D8A607c3b11f2aF50A0f239Bd71CD0" as `0x${string}`;
  const DATAFEEDS_USDT_USD =
    "0xB97Ad0E74fa7d920791E90258A6E2085088b4320" as `0x${string}`;
  const DATAFEEDS_USDC_USD =
    "0x51597f405303C4377E36123cBc172b13269EA163" as `0x${string}`;

  const userWallet = walletClient.account.address;

  const USDT_WHALE =
    "0x092FE28430BaDe62C7C044B9C77d0aaa06241319" as `0x${string}`;

  const GHKE_SWAP_AMOUNT = parseUnits("200", GHKE_DECIMALS);

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

    const GHKESwapPool = await viem.deployContract("GHKESwapPool");
    await GHKESwapPool.write.initialize([
      GHKE.address,
      USDT.address,
      DATAFEEDS_USDT_USD,
      GHKBuyPool.address,
    ]);
    // await GHKESwapPool.write.setDataFeedUSDT_USD([DATAFEEDS_USDT_USD]);

    // 1/2 GHKBuyPool 合约设置 GHKE_BUY_POOL 地址
    await GHKBuyPool.write.setGHKE_BUY_POOL([GHKESwapPool.address]);
    // 2/2开启 swap 功能
    await GHKESwapPool.write.setStop([false]);

    // 将 GHK 转入 GHKBuyPool 合约
    await GHK.write.transfer([GHKBuyPool.address, 10_000n * 10n ** 18n]);
    // 从鲸鱼账号给 GHKESwapPool 转 USDT USDC
    await networkHelpers.impersonateAccount(USDT_WHALE);
    await networkHelpers.setBalance(USDT_WHALE, parseEther("1"));
    await USDT.write.transfer(
      [GHKESwapPool.address, parseUnits("10000", USDT_DECIMALS)],
      {
        account: USDT_WHALE,
      }
    );

    {
      const GHK_GHKBuyPoolBalance = await GHK.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const GHK_GHKESwapPoolBalance = await GHK.read.balanceOf([
        GHKESwapPool.address,
      ]);
      const GHK_UserBalance = await GHK.read.balanceOf([userWallet]);

      const GHKE_GHKBuyPoolBalance = await GHKE.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const GHKE_GHKESwapPoolBalance = await GHKE.read.balanceOf([
        GHKESwapPool.address,
      ]);
      const GHKE_UserBalance = await GHKE.read.balanceOf([userWallet]);

      const USDT_GHKBuyPoolBalance = await USDT.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const USDT_GHKESwapPoolBalance = await USDT.read.balanceOf([
        GHKESwapPool.address,
      ]);
      const USDT_UserBalance = await USDT.read.balanceOf([userWallet]);

      const USDC_GHKBuyPoolBalance = await USDC.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const USDC_GHKESwapPoolBalance = await USDC.read.balanceOf([
        GHKESwapPool.address,
      ]);
      const USDC_UserBalance = await USDC.read.balanceOf([userWallet]);

      console.log("初始状态：");
      console.log(" GHK-GHKBuyPool:", GHK_GHKBuyPoolBalance);
      console.log(" GHK-GHKESwapPool:", GHK_GHKESwapPoolBalance);
      console.log(" GHK-User:", GHK_UserBalance);
      console.log(" GHKE-GHKBuyPool:", GHKE_GHKBuyPoolBalance);
      console.log(" GHKE-GHKESwapPool:", GHKE_GHKESwapPoolBalance);
      console.log(" GHKE-User:", GHKE_UserBalance);
      console.log(" USDT-GHKBuyPool:", USDT_GHKBuyPoolBalance);
      console.log(" USDT-GHKESwapPool:", USDT_GHKESwapPoolBalance);
      console.log(" USDT-User:", USDT_UserBalance);
      console.log(" USDC-GHKBuyPool:", USDC_GHKBuyPoolBalance);
      console.log(" USDC-GHKESwapPool:", USDC_GHKESwapPoolBalance);
      console.log(" USDC-User:", USDC_UserBalance);
    }

    console.log("sender:", userWallet);
    console.log("GHK:", GHK.address, "GHKE:", GHKE.address);
    console.log("USDT:", USDT.address, "USDC:", USDC.address);
    console.log(
      "GHKBuyPool:",
      GHKBuyPool.address,
      "GHKESwapPool:",
      GHKESwapPool.address
    );

    return { GHK, GHKE, USDT, USDC, GHKBuyPool, GHKESwapPool };
  }

  it("swap", async () => {
    const { GHK, GHKE, USDT, USDC, GHKBuyPool, GHKESwapPool } =
      await networkHelpers.loadFixture(deployContractsFixture);

    const offchainPriceData = await getOffchainXAUPrice();
    console.log("Offchain XAU price data:", offchainPriceData);
    const offchainPrice = BigInt(offchainPriceData.ask * 1e18); // chainlink 预言机的价格精度都是 8 位，但在链上都处理成了 18 位所以这里要乘以 1e18 转换为 18 位精度
    const deadline = BigInt(offchainPriceData.timestamp + 30);
    const sig = await sign(walletClient, offchainPrice, deadline, userWallet);

    const usdtPrice = await GHKBuyPool.read.getUsdtPrice();
    console.log("USDT price:", usdtPrice.toString());

    const usdcPrice = await GHKBuyPool.read.getUsdcPrice();
    console.log("USDC price:", usdcPrice.toString());

    const amountOut = await GHKESwapPool.read.getAmountOut([
      GHKE_SWAP_AMOUNT,
      offchainPrice,
    ]);
    console.log("getAmountOut:", amountOut.toString());

    await GHKE.write.approve([GHKESwapPool.address, GHKE_SWAP_AMOUNT * 2n]);

    console.log(
      "userWallet:",
      userWallet,
      "GHKESwapPool:",
      GHKESwapPool.address,
      "allowance:",
      await GHKE.read.allowance([userWallet, GHKESwapPool.address])
    );

    await GHKESwapPool.write.swap([
      GHKE_SWAP_AMOUNT,
      offchainPrice,
      deadline,
      sig,
    ]);

    {
      const GHK_GHKBuyPoolBalance = await GHK.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const GHK_GHKESwapPoolBalance = await GHK.read.balanceOf([
        GHKESwapPool.address,
      ]);
      const GHK_UserBalance = await GHK.read.balanceOf([userWallet]);

      const GHKE_GHKBuyPoolBalance = await GHKE.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const GHKE_GHKESwapPoolBalance = await GHKE.read.balanceOf([
        GHKESwapPool.address,
      ]);
      const GHKE_UserBalance = await GHKE.read.balanceOf([userWallet]);

      const USDT_GHKBuyPoolBalance = await USDT.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const USDT_GHKESwapPoolBalance = await USDT.read.balanceOf([
        GHKESwapPool.address,
      ]);
      const USDT_UserBalance = await USDT.read.balanceOf([userWallet]);

      const USDC_GHKBuyPoolBalance = await USDC.read.balanceOf([
        GHKBuyPool.address,
      ]);
      const USDC_GHKESwapPoolBalance = await USDC.read.balanceOf([
        GHKESwapPool.address,
      ]);
      const USDC_UserBalance = await USDC.read.balanceOf([userWallet]);

      console.log("从 GHKE-> GHK 兑换后的状态：");
      console.log(" GHK-GHKBuyPool:", GHK_GHKBuyPoolBalance);
      console.log(" GHK-GHKESwapPool:", GHK_GHKESwapPoolBalance);
      console.log(" GHK-User:", GHK_UserBalance);
      console.log(" GHKE-GHKBuyPool:", GHKE_GHKBuyPoolBalance);
      console.log(" GHKE-GHKESwapPool:", GHKE_GHKESwapPoolBalance);
      console.log(" GHKE-User:", GHKE_UserBalance);
      console.log(" USDT-GHKBuyPool:", USDT_GHKBuyPoolBalance);
      console.log(" USDT-GHKESwapPool:", USDT_GHKESwapPoolBalance);
      console.log(" USDT-User:", USDT_UserBalance);
      console.log(" USDC-GHKBuyPool:", USDC_GHKBuyPoolBalance);
      console.log(" USDC-GHKESwapPool:", USDC_GHKESwapPoolBalance);
      console.log(" USDC-User:", USDC_UserBalance);
    }
  });
});
