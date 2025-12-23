import { describe, it } from "node:test";
import { network } from "hardhat";
import { parseUnits } from "viem";

describe("GHKBuyPool", async () => {
  const { viem, networkHelpers } = await network.connect();
  const [walletClient] = await viem.getWalletClients();

  const userWallet = walletClient.account.address;

  const GHK_DECIMALS = 18;

  const GHK_STAKE_AMOUNT = parseUnits("2000", GHK_DECIMALS);

  async function deployContractsFixture() {
    const GHK = await viem.deployContract("GHKToken");
    await GHK.write.initialize([10_000n]);

    const GHKE = await viem.deployContract("GHKEToken");
    await GHKE.write.initialize();

    const GHKMiningPool = await viem.deployContract("GHKMiningPool");
    await GHKMiningPool.write.initialize([GHK.address, GHKE.address]);

    // 将 GHKE 转入 GHKMiningPool 合约
    await GHKE.write.transfer([
      GHKMiningPool.address,
      1_000_000_000n * 10n ** 18n,
    ]);

    {
      const GHK_GHKMiningPoolBalance = await GHK.read.balanceOf([
        GHKMiningPool.address,
      ]);
      const GHK_UserBalance = await GHK.read.balanceOf([userWallet]);

      const GHKE_GHKMiningPoolBalance = await GHKE.read.balanceOf([
        GHKMiningPool.address,
      ]);
      const GHKE_UserBalance = await GHKE.read.balanceOf([userWallet]);

      console.log("初始状态：");
      console.log(" GHK-GHKMiningPool:", GHK_GHKMiningPoolBalance);
      console.log(" GHK-User:", GHK_UserBalance);
      console.log(" GHKE-GHKMiningPool:", GHKE_GHKMiningPoolBalance);
      console.log(" GHKE-User:", GHKE_UserBalance);
    }

    return { GHK, GHKE, GHKMiningPool };
  }

  it("deposit", async () => {
    const { GHK, GHKE, GHKMiningPool } = await networkHelpers.loadFixture(
      deployContractsFixture
    );

    await GHK.write.approve([GHKMiningPool.address, GHK_STAKE_AMOUNT * 2n]);
    await GHKMiningPool.write.deposit([GHK_STAKE_AMOUNT]);

    {
      const GHK_GHKMiningPoolBalance = await GHK.read.balanceOf([
        GHKMiningPool.address,
      ]);
      const GHK_UserBalance = await GHK.read.balanceOf([userWallet]);

      const GHKE_GHKMiningPoolBalance = await GHKE.read.balanceOf([
        GHKMiningPool.address,
      ]);
      const GHKE_UserBalance = await GHKE.read.balanceOf([userWallet]);

      console.log("质押之后的状态：");
      console.log(" GHK-GHKMiningPool:", GHK_GHKMiningPoolBalance);
      console.log(" GHK-User:", GHK_UserBalance);
      console.log(" GHKE-GHKMiningPool:", GHKE_GHKMiningPoolBalance);
      console.log(" GHKE-User:", GHKE_UserBalance);
    }
  });
});
