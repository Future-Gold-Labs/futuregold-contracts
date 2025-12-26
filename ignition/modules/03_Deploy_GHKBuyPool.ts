import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import GHKToken from "./01_Deploy_GHKToken.js";
import GHKEToken from "./02_Deploy_GHKEToken.js";

export default buildModule("GHKBuyPool", (m) => {
  const { proxy: ghkToken } = m.useModule(GHKToken);
  const { proxy: ghkeToken } = m.useModule(GHKEToken);

  const owner = m.getAccount(0);

  const ghkBuyPool = m.contract("GHKBuyPool");

  // constructor(address _logic, address initialOwner, bytes memory _data)
  const proxy = m.contract("TransparentUpgradeableProxy", [
    ghkBuyPool,
    owner,
    // function initialize(address _usdToAddress, address _GHK, address _GHKE, address _USDT, address _USDC,
    //  address _dataFeedXAU, address _dataFeedUSDT, address _dataFeedUSDC,
    //  uint256 _initialXAUPrice, address _signer) public initializer {}
    m.encodeFunctionCall(ghkBuyPool, "initialize", [
      m.getParameter("USD_TO_ADDRESS"),
      ghkToken,
      ghkeToken,
      m.getParameter("USDT"),
      m.getParameter("USDC"),
      m.getParameter("DATA_FEED_XAU"),
      m.getParameter("DATA_FEED_USDT"),
      m.getParameter("DATA_FEED_USDC"),
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

  return { ghkBuyPool, proxy, proxyAdmin };
});
