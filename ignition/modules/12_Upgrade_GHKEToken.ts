import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import GHKEToken from "./02_Deploy_GHKEToken.js";

export default buildModule("Upgrade_GHKEToken", (m) => {
  const owner = m.getAccount(0);

  const { proxy, proxyAdmin } = m.useModule(GHKEToken);

  const ghkeToken = m.contract("GHKEToken");

  // function upgradeAndCall(ITransparentUpgradeableProxy proxy, address implementation, bytes memory data) public payable virtual onlyOwner
  m.call(proxyAdmin, "upgradeAndCall", [proxy, ghkeToken, "0x"], {
    from: owner,
  });

  return { ghkeToken };
});
