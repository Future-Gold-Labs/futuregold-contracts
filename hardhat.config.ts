import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable, defineConfig } from "hardhat/config";
import hardhatReownPlugin from "hardhat-reown";
import hardhatVerify from "@nomicfoundation/hardhat-verify";

export default defineConfig({
  plugins: [hardhatToolboxViemPlugin, hardhatReownPlugin, hardhatVerify],
  ignition: {
    requiredConfirmations: 1, // 一个确认就够了
  },
  solidity: {
    npmFilesToBuild: [
      "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol",
      "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol",
    ],
    profiles: {
      default: {
        version: "0.8.30",
        settings: {
          optimizer: {
            enabled: true,
            runs: 999,
          },
          viaIR: true,
        },
      },
    },
  },
  networks: {
    // 只有单元测试使用 hardhat 网络：`bunx hardhat test nodejs --network hardhat`
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
    bnbTestnet: {
      type: "http",
      chainType: "l1",
      url: "https://bsc-testnet-rpc.publicnode.com",
      reownAccounts: true,
      // accounts: ["0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"],
    },
    bnb: {
      type: "http",
      chainType: "l1",
      url: "https://go.getblock.asia/8d79e88e815c4a43b4d3fd168c9ebd9d",
      reownAccounts: true,
    },
  },
  verify: {
    etherscan: {
      apiKey: "1W6UNEYEZ4217QQE8JVR6M95ZRGC9STYA4",
    },
    blockscout: {
      enabled: false,
    },
    sourcify: {
      enabled: false,
    },
  },
});
