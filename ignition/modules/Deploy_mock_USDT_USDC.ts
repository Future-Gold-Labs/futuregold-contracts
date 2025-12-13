import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("MOCK_USDT_USDC", (m) => {
  const USDT = m.contract("BEP20USDT");
  const USDC = m.contract("BEP20USDC");

  return { USDT, USDC };
});
