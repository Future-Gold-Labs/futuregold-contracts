import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import GHKESwapPool from "./07_Deploy_GHKESwapPool.js";

export default buildModule("Upgrade_GHKESwapPool", (m) => {
  const owner = m.getAccount(0);

  const { proxy, proxyAdmin } = m.useModule(GHKESwapPool);

  const ghkeSwapPool = m.contract("GHKESwapPool");

  // function upgradeAndCall(ITransparentUpgradeableProxy proxy, address implementation, bytes memory data) public payable virtual onlyOwner
  m.call(proxyAdmin, "upgradeAndCall", [proxy, ghkeSwapPool, "0x"], {
    from: owner,
  });

  return { ghkeSwapPool };
});
