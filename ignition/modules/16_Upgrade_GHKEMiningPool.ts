import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import GHKEMiningPool from "./06_Deploy_GHKEMiningPool.js";

export default buildModule("Upgrade_GHKEMiningPool", (m) => {
  const owner = m.getAccount(0);

  const { proxy, proxyAdmin } = m.useModule(GHKEMiningPool);

  const ghkeMiningPool = m.contract("GHKEMiningPool");

  // function upgradeAndCall(ITransparentUpgradeableProxy proxy, address implementation, bytes memory data) public payable virtual onlyOwner
  m.call(proxyAdmin, "upgradeAndCall", [proxy, ghkeMiningPool, "0x"], {
    from: owner,
  });

  return { ghkeMiningPool };
});
