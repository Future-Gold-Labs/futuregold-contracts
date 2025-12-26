import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("GHKToken", (m) => {
  const owner = m.getAccount(0);

  const ghkToken = m.contract("GHKToken");

  // constructor(address _logic, address initialOwner, bytes memory _data)
  const proxy = m.contract("TransparentUpgradeableProxy", [
    ghkToken,
    owner,
    // function initialize(uint256 initialSupply) public initializer {}
    m.encodeFunctionCall(ghkToken, "initialize", [
      1000_000n, // 100w
    ]),
  ]);

  const proxyAdminAddress = m.readEventArgument(
    proxy,
    "AdminChanged",
    "newAdmin"
  );
  const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress);

  return { ghkToken, proxy, proxyAdmin };
});
