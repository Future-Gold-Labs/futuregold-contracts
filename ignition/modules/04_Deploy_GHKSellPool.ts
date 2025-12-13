import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import GHKToken from "./01_Deploy_GHKToken.js";

export default buildModule("GHKSellPool", (m) => {
  const { proxy: ghkToken } = m.useModule(GHKToken);

  const owner = m.getAccount(0);

  const ghkSellPool = m.contract("GHKSellPool");

  // constructor(address _logic, address initialOwner, bytes memory _data)
  const proxy = m.contract("TransparentUpgradeableProxy", [
    ghkSellPool,
    owner,
    // function initialize(address _GHK, address _USDT, address _XAU_USD, uint256 _initialXAUPrice, address _signer) public initializer {}
    m.encodeFunctionCall(ghkSellPool, "initialize", [
      ghkToken,
      m.getParameter("USDT"),
      m.getParameter("DATA_FEED_XAU"),
      m.getParameter("INITIAL_XAU_PRICE"),
      m.getParameter("SIGNER"),
    ]),
  ]);

  const proxyAdminAddress = m.readEventArgument(
    proxy,
    "AdminChanged",
    "newAdmin"
  );
  const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress);

  return { ghkSellPool, proxy, proxyAdmin };
});
