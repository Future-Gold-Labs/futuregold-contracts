import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable, defineConfig } from "hardhat/config";
import hardhatReownPlugin from "hardhat-reown";

export default defineConfig({
  plugins: [hardhatToolboxViemPlugin, hardhatReownPlugin],
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
      // accounts: {
      //   mnemonic: configVariable("METAMASK_MNEMONIC_DEV"),
      //   initialIndex: 0,
      // },
      // ignition: {
      //   gasPrice: 900984013107n,
      // },
    },
  },
});
