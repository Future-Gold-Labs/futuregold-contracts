import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";

import { getOffchainXAUPrice, sign } from "./helper.js";
import { getContract, parseAbi, parseEther, parseUnits } from "viem";

describe("GHKSellPool", async () => {
  const { viem, networkHelpers } = await network.connect();
  const [walletClient] = await viem.getWalletClients();

  const USDT_ADDR =
    "0x55d398326f99059ff775485246999027b3197955" as `0x${string}`;

  const USDT_DECIMALS = 18;
  const GHK_DECIMALS = 18;

  const DATAFEEDS_XAU_USD =
    "0x86896fEB19D8A607c3b11f2aF50A0f239Bd71CD0" as `0x${string}`;
  const DATAFEEDS_USDT_USD =
    "0xB97Ad0E74fa7d920791E90258A6E2085088b4320" as `0x${string}`;

  const userWallet = walletClient.account.address;

  const USDT_WHALE =
    "0x092FE28430BaDe62C7C044B9C77d0aaa06241319" as `0x${string}`;

  const SELL_GHK_AMOUNT1 = parseUnits("1", GHK_DECIMALS); // 1 GHK
  const SELL_GHK_AMOUNT10 = parseUnits("10", GHK_DECIMALS); // 10 GHK

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

    const GHK = await viem.deployContract("GHKToken");
    await GHK.write.initialize([10_000n]);

    const GHKSellPool = await viem.deployContract("GHKSellPool");
    await GHKSellPool.write.initialize([
      GHK.address,
      USDT.address,
      DATAFEEDS_XAU_USD,
      DATAFEEDS_USDT_USD,
      4202_242759559214530560n,
      // 3202_242759559214530560n,
      userWallet,
    ]);
    // await GHKSellPool.write.setDataFeedUSDT_USD([DATAFEEDS_USDT_USD]);

    // 从鲸鱼账号给 GHKSellPool 转 USDT
    await networkHelpers.impersonateAccount(USDT_WHALE);
    await networkHelpers.setBalance(USDT_WHALE, parseEther("1"));
    await USDT.write.transfer(
      [GHKSellPool.address, parseUnits("100000", USDT_DECIMALS)],
      {
        account: USDT_WHALE,
      }
    );

    {
      const GHK_GHKSellPoolBalance = await GHK.read.balanceOf([
        GHKSellPool.address,
      ]);
      const GHK_UserBalance = await GHK.read.balanceOf([userWallet]);

      const USDT_GHKSellPoolBalance = await USDT.read.balanceOf([
        GHKSellPool.address,
      ]);
      const USDT_UserBalance = await USDT.read.balanceOf([userWallet]);

      console.log("初始状态：");
      console.log(" GHK-GHKSellPool:", GHK_GHKSellPoolBalance);
      console.log(" GHK-User:", GHK_UserBalance);
      console.log(" USDT-GHKSellPool:", USDT_GHKSellPoolBalance);
      console.log(" USDT-User:", USDT_UserBalance);
    }

    return { GHK, USDT, GHKSellPool };
  }

  it("sell", async () => {
    const { GHK, USDT, GHKSellPool } = await networkHelpers.loadFixture(
      deployContractsFixture
    );

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

    const gXAUPrice = await GHKSellPool.read.getPrice([offchainPrice]);
    console.log("XAU/g price (USDT):", gXAUPrice.toString());

    await GHK.write.approve([GHKSellPool.address, SELL_GHK_AMOUNT1]);
    await GHKSellPool.write.sell([
      SELL_GHK_AMOUNT1,
      USDT.address,
      offchainPrice,
      deadline,
      sig,
    ]);

    {
      const GHK_GHKSellPoolBalance = await GHK.read.balanceOf([
        GHKSellPool.address,
      ]);
      const GHK_UserBalance = await GHK.read.balanceOf([userWallet]);

      const USDT_GHKSellPoolBalance = await USDT.read.balanceOf([
        GHKSellPool.address,
      ]);
      const USDT_UserBalance = await USDT.read.balanceOf([userWallet]);

      console.log("卖出 GHK 后的状态：");
      console.log(" GHK-GHKSellPool:", GHK_GHKSellPoolBalance);
      console.log(" GHK-User:", GHK_UserBalance);
      console.log(" USDT-GHKSellPool:", USDT_GHKSellPoolBalance);
      console.log(" USDT-User:", USDT_UserBalance);
    }
  });
  it("sellOffline", async () => {
    const { GHK, USDT, GHKSellPool } = await networkHelpers.loadFixture(
      deployContractsFixture
    );

    const offchainPriceData = await getOffchainXAUPrice();
    console.log("Offchain XAU price data:", offchainPriceData);
    const offchainPrice = BigInt(offchainPriceData.ask * 1e18); // chainlink 预言机的价格精度都是 8 位，但在链上都处理成了 18 位所以这里要乘以 1e18 转换为 18 位精度

    const gXAUPrice = await GHKSellPool.read.getPrice([offchainPrice]);
    console.log("XAU/g price (USDT):", gXAUPrice.toString());

    await GHK.write.approve([GHKSellPool.address, SELL_GHK_AMOUNT10]);
    await GHKSellPool.write.sellOffline([SELL_GHK_AMOUNT10]);

    {
      const GHK_GHKSellPoolBalance = await GHK.read.balanceOf([
        GHKSellPool.address,
      ]);
      const GHK_UserBalance = await GHK.read.balanceOf([userWallet]);

      const USDT_GHKSellPoolBalance = await USDT.read.balanceOf([
        GHKSellPool.address,
      ]);
      const USDT_UserBalance = await USDT.read.balanceOf([userWallet]);

      console.log("卖出 GHK 后的状态：");
      console.log(" GHK-GHKSellPool:", GHK_GHKSellPoolBalance);
      console.log(" GHK-User:", GHK_UserBalance);
      console.log(" USDT-GHKSellPool:", USDT_GHKSellPoolBalance);
      console.log(" USDT-User:", USDT_UserBalance);
    }
  });
});
