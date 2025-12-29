import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import GHKMiningPool from "./05_Deploy_GHKMiningPool.js";

export default buildModule("Upgrade_GHKMiningPool", (m) => {
  const owner = m.getAccount(0);

  const { proxy, proxyAdmin } = m.useModule(GHKMiningPool);

  const gkhMiningPool = m.contract("GHKMiningPool");

  // function upgradeAndCall(ITransparentUpgradeableProxy proxy, address implementation, bytes memory data) public payable virtual onlyOwner
  m.call(proxyAdmin, "upgradeAndCall", [proxy, gkhMiningPool, "0x"], {
    from: owner,
  });

  return { gkhMiningPool };
});
