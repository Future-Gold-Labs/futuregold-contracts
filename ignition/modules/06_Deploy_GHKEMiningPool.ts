import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import GHKEToken from "./02_Deploy_GHKEToken.js";

export default buildModule("GHKEMiningPool", (m) => {
  const { proxy: ghkeToken } = m.useModule(GHKEToken);

  const owner = m.getAccount(0);

  const gkheMiningPool = m.contract("GHKEMiningPool");

  // constructor(address _logic, address initialOwner, bytes memory _data)
  const proxy = m.contract("TransparentUpgradeableProxy", [
    gkheMiningPool,
    owner,
    // function initialize(address _ghkToken, address _ghkeToken) public initializer {}
    m.encodeFunctionCall(gkheMiningPool, "initialize", [ghkeToken, ghkeToken]),
  ]);

  const proxyAdminAddress = m.readEventArgument(
    proxy,
    "AdminChanged",
    "newAdmin"
  );
  const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress);

  return { gkheMiningPool, proxy, proxyAdmin };
});
