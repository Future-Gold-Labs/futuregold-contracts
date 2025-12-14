
`bunx hardhat ignition deploy ignition/modules/Deploy_mock_USDT_USDC.ts --build-profile default --network bnbTestnet`


## 1. 部署

`bunx hardhat ignition deploy ignition/modules/01_Deploy_GHKToken.ts --build-profile default --network bnbTestnet`

`bunx hardhat ignition deploy ignition/modules/02_Deploy_GHKEToken.ts --build-profile default --network bnbTestnet`

`bunx hardhat ignition deploy ignition/modules/03_Deploy_GHKBuyPool.ts --build-profile default --network bnbTestnet --parameters ignition/parameters.bnb.testnet.json`

`bunx hardhat ignition deploy ignition/modules/04_Deploy_GHKSellPool.ts --build-profile default --network bnbTestnet --parameters ignition/parameters.bnb.testnet.json`

`bunx hardhat ignition deploy ignition/modules/05_Deploy_GHKMiningPool.ts --build-profile default --network bnbTestnet`

`bunx hardhat ignition deploy ignition/modules/06_Deploy_GHKEMiningPool.ts --build-profile default --network bnbTestnet`

`bunx hardhat ignition deploy ignition/modules/07_Deploy_GHKESwapPool.ts --build-profile default --network bnbTestnet --parameters ignition/parameters.bnb.testnet.json`

## 2. 升级

`bunx hardhat ignition deploy ignition/modules/13_Upgrade_GHKBuyPool.ts --build-profile default --network bnbTestnet --parameters ignition/parameters.bnb.testnet.json`


`bunx hardhat ignition deploy ignition/modules/14_Upgrade_GHKSellPool.ts --build-profile default --network bnbTestnet --parameters ignition/parameters.bnb.testnet.json`
