import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("GHKEToken", (m) => {
  const owner = m.getAccount(0);

  const ghkeToken = m.contract("GHKEToken");

  // constructor(address _logic, address initialOwner, bytes memory _data)
  const proxy = m.contract("TransparentUpgradeableProxy", [
    ghkeToken,
    owner,
    // function initialize() public initializer {}
    m.encodeFunctionCall(ghkeToken, "initialize"),
  ]);

  const proxyAdminAddress = m.readEventArgument(
    proxy,
    "AdminChanged",
    "newAdmin"
  );
  const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress);

  return { ghkeToken, proxy, proxyAdmin };
});
