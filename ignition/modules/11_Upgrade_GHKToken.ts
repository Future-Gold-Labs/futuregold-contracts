import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import GHKToken from "./01_Deploy_GHKToken.js";

export default buildModule("Upgrade_GHKToken", (m) => {
  const owner = m.getAccount(0);

  const { proxy, proxyAdmin } = m.useModule(GHKToken);

  const ghkToken = m.contract("GHKToken");

  // function upgradeAndCall(ITransparentUpgradeableProxy proxy, address implementation, bytes memory data) public payable virtual onlyOwner
  m.call(proxyAdmin, "upgradeAndCall", [proxy, ghkToken, "0x"], {
    from: owner,
  });

  return { ghkToken };
});
