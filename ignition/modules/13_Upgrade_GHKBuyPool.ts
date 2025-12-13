import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import GHKBuyPool from "./03_Deploy_GHKBuyPool.js";

export default buildModule("Upgrade_GHKBuyPool", (m) => {
  const owner = m.getAccount(0);

  const { proxy, proxyAdmin } = m.useModule(GHKBuyPool);

  const ghkBuyPool = m.contract("GHKBuyPool");

  // function upgradeAndCall(ITransparentUpgradeableProxy proxy, address implementation, bytes memory data) public payable virtual onlyOwner
  m.call(proxyAdmin, "upgradeAndCall", [proxy, ghkBuyPool, "0x"], {
    from: owner,
  });

  return { ghkBuyPool };
});
