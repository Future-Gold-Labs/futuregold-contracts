import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import GHKSellPool from "./04_Deploy_GHKSellPool.js";

export default buildModule("Upgrade_GHKSellPool", (m) => {
  const owner = m.getAccount(0);

  const { proxy, proxyAdmin } = m.useModule(GHKSellPool);

  const ghkSellPool = m.contract("GHKSellPool");

  // function upgradeAndCall(ITransparentUpgradeableProxy proxy, address implementation, bytes memory data) public payable virtual onlyOwner
  m.call(proxyAdmin, "upgradeAndCall", [proxy, ghkSellPool, "0x"], {
    from: owner,
  });

  return { ghkSellPool };
});
