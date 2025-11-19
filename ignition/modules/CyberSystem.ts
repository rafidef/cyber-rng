import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const CyberSystemModule = buildModule("CyberSystemModule", (m) => {
  const hashToken = m.contract("HashToken");
  const game = m.contract("CyberArtifacts", [hashToken]);
  m.call(hashToken, "transferOwnership", [game]);
  return { hashToken, game };
});

export default CyberSystemModule;