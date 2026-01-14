import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import GHKEToken from "./02_Deploy_GHKEToken.js";
import GHKBuyPool from "./03_Deploy_GHKBuyPool.js";

export default buildModule("GHKESwapPool", (m) => {
  const { proxy: ghkeToken } = m.useModule(GHKEToken);
  const { proxy: ghkBuyPool } = m.useModule(GHKBuyPool);

  const owner = m.getAccount(0);

  const ghkeSwapPool = m.contract("GHKESwapPool");

  // constructor(address _logic, address initialOwner, bytes memory _data)
  const proxy = m.contract("TransparentUpgradeableProxy", [
    ghkeSwapPool,
    owner,
    // function initialize(address _usdToAddress, address _GHKE, address _USDT, address _dataFeedUSDT,
    //  address _GHK_BUY_POOL_ADDRESS) public initializer {}
    m.encodeFunctionCall(ghkeSwapPool, "initialize", [
      m.getParameter("USD_TO_ADDRESS"),
      ghkeToken,
      m.getParameter("USDT"),
      m.getParameter("DATA_FEED_USDT"),
      ghkBuyPool,
    ]),
  ]);

  const proxyAdminAddress = m.readEventArgument(
    proxy,
    "AdminChanged",
    "newAdmin"
  );
  const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress);

  // ！！！！！！！ 未测试 ！！！！！！！
  // const tx = m.call(ghkBuyPool, "setGHKESwapPool", [proxy], { from: owner });
  // console.log("Call GHKBuyPool.setGHKESwapPool(pool) success, tx:", tx);

  return { ghkeSwapPool, proxy, proxyAdmin };
});
