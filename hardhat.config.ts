import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable, defineConfig } from "hardhat/config";

export default defineConfig({
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.30",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          viaIR: true,
        },
      },
    },
  },
  networks: {
    // 只有单元测试使用 hardhat 网络：`npx hardhat test nodejs --network hardhat`
    hardhat: {
      type: "edr-simulated",
      chainType: "l1",
      forking: {
        url: configVariable("ALCHEMY_RPC_BNB_DEV"),
        blockNumber: 71170971,
        // url: "https://bnb-testnet.g.alchemy.com/v2/3gXuij3_Htk8Kyf0VnMv7",
        // blockNumber: 71070806,
      },
    },
    bscTestnet: {
      type: "http",
      chainType: "l1",
      url: "https://bnb-testnet.g.alchemy.com/v2/3gXuij3_Htk8Kyf0VnMv7",
      accounts: {
        mnemonic: configVariable("METAMASK_MNEMONIC_DEV"),
        initialIndex: 0,
      },
    },
  },
});
