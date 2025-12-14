import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import GHKToken from "./01_Deploy_GHKToken.js";
import GHKEToken from "./02_Deploy_GHKEToken.js";

export default buildModule("GHKMiningPool", (m) => {
  const { proxy: ghkToken } = m.useModule(GHKToken);
  const { proxy: ghkeToken } = m.useModule(GHKEToken);

  const owner = m.getAccount(0);

  const gkhMiningPool = m.contract("GHKMiningPool");

  // constructor(address _logic, address initialOwner, bytes memory _data)
  const proxy = m.contract("TransparentUpgradeableProxy", [
    gkhMiningPool,
    owner,
    // function initialize(address _ghkToken, address _ghkeToken) public initializer {}
    m.encodeFunctionCall(gkhMiningPool, "initialize", [ghkToken, ghkeToken]),
  ]);

  const proxyAdminAddress = m.readEventArgument(
    proxy,
    "AdminChanged",
    "newAdmin"
  );
  const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress);

  return { gkhMiningPool, proxy, proxyAdmin };
});
